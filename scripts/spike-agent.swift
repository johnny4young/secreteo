// Spike 1 helper, compiled by scripts/spike_two_apps.py. It records times and counts only:
// never audio it captured, words it read from a panel, or text it received.
import AppKit
import ApplicationServices
import AVFoundation
import Carbon.HIToolbox
import CoreAudio
import Foundation

func emit(_ object: [String: Any], to handle: FileHandle = .standardOutput) {
    guard var data = try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]) else { return }
    data.append(0x0A)
    handle.write(data)
}

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data(("spike-agent: " + message + "\n").utf8))
    exit(2)
}

func option(_ name: String, in arguments: [String]) -> String? {
    guard let index = arguments.firstIndex(of: name), arguments.indices.contains(index + 1) else { return nil }
    return arguments[index + 1]
}

func wordCount(_ text: String) -> Int {
    text.split(whereSeparator: { $0.isWhitespace || $0.isNewline }).count
}

// MARK: Audio devices

struct AudioDevice {
    let id: AudioDeviceID
    let name: String
    let uid: String
    let inputs: Int
    let outputs: Int
}

func stringProperty(_ device: AudioDeviceID, _ selector: AudioObjectPropertySelector) -> String {
    var address = AudioObjectPropertyAddress(
        mSelector: selector, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
    var value: Unmanaged<CFString>?
    var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
    guard AudioObjectGetPropertyData(device, &address, 0, nil, &size, &value) == noErr,
          let value else { return "" }
    return value.takeRetainedValue() as String
}

func channelCount(_ device: AudioDeviceID, scope: AudioObjectPropertyScope) -> Int {
    var address = AudioObjectPropertyAddress(
        mSelector: kAudioDevicePropertyStreamConfiguration, mScope: scope, mElement: kAudioObjectPropertyElementMain)
    var size: UInt32 = 0
    guard AudioObjectGetPropertyDataSize(device, &address, 0, nil, &size) == noErr, size > 0 else { return 0 }
    let raw = UnsafeMutableRawPointer.allocate(byteCount: Int(size), alignment: 16)
    defer { raw.deallocate() }
    guard AudioObjectGetPropertyData(device, &address, 0, nil, &size, raw) == noErr else { return 0 }
    let list = UnsafeMutableAudioBufferListPointer(raw.assumingMemoryBound(to: AudioBufferList.self))
    return list.reduce(0) { $0 + Int($1.mNumberChannels) }
}

func audioDevices() -> [AudioDevice] {
    var address = AudioObjectPropertyAddress(
        mSelector: kAudioHardwarePropertyDevices, mScope: kAudioObjectPropertyScopeGlobal,
        mElement: kAudioObjectPropertyElementMain)
    var size: UInt32 = 0
    guard AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size) == noErr
    else { return [] }
    var ids = [AudioDeviceID](repeating: 0, count: Int(size) / MemoryLayout<AudioDeviceID>.size)
    guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &ids) == noErr
    else { return [] }
    return ids.map {
        AudioDevice(
            id: $0, name: stringProperty($0, kAudioObjectPropertyName), uid: stringProperty($0, kAudioDevicePropertyDeviceUID),
            inputs: channelCount($0, scope: kAudioObjectPropertyScopeInput),
            outputs: channelCount($0, scope: kAudioObjectPropertyScopeOutput))
    }
}

// MARK: check

func check(_ arguments: [String]) {
    var report: [String: Any] = [
        "accessibilityTrusted": AXIsProcessTrusted(),
        "devices": audioDevices().map {
            ["name": $0.name, "uid": $0.uid, "inputChannels": $0.inputs, "outputChannels": $0.outputs]
        },
    ]
    if let path = option("--wav", in: arguments) {
        let file = try? AVAudioFile(forReading: URL(fileURLWithPath: path))
        report["wavFrames"] = file.map { Int($0.length) } ?? -1
    }
    emit(report)
}

// MARK: play

func play(_ arguments: [String]) {
    guard let name = option("--device", in: arguments), let path = option("--file", in: arguments) else {
        fail("play needs --device and --file")
    }
    guard let device = audioDevices().first(where: { $0.name == name && $0.outputs > 0 }) else {
        fail("no output device named \(name)")
    }
    guard let file = try? AVAudioFile(forReading: URL(fileURLWithPath: path)) else { fail("unreadable audio file") }
    let engine = AVAudioEngine()
    guard let unit = engine.outputNode.audioUnit else { fail("no output unit") }
    var deviceID = device.id
    let status = AudioUnitSetProperty(
        unit, kAudioOutputUnitProperty_CurrentDevice, kAudioUnitScope_Global, 0,
        &deviceID, UInt32(MemoryLayout<AudioDeviceID>.size))
    guard status == noErr else { fail("cannot route to \(name): \(status)") }
    let player = AVAudioPlayerNode()
    engine.attach(player)
    engine.connect(player, to: engine.mainMixerNode, format: file.processingFormat)
    let done = DispatchSemaphore(value: 0)
    player.scheduleFile(file, at: nil, completionCallbackType: .dataPlayedBack) { _ in done.signal() }
    do { try engine.start() } catch { fail("engine did not start") }
    player.play()
    let started = Date().timeIntervalSince1970
    let seconds = Double(file.length) / file.processingFormat.sampleRate
    if done.wait(timeout: .now() + seconds + 10) == .timedOut { fail("playback did not finish") }
    let ended = Date().timeIntervalSince1970
    engine.stop()
    emit(["startedAt": started, "endedAt": ended, "frames": Int(file.length),
          "sampleRate": file.processingFormat.sampleRate])
}

// MARK: key

let keyCodes: [String: Int] = [
    "a": kVK_ANSI_A, "b": kVK_ANSI_B, "c": kVK_ANSI_C, "d": kVK_ANSI_D, "e": kVK_ANSI_E, "f": kVK_ANSI_F,
    "g": kVK_ANSI_G, "h": kVK_ANSI_H, "i": kVK_ANSI_I, "j": kVK_ANSI_J, "k": kVK_ANSI_K, "l": kVK_ANSI_L,
    "m": kVK_ANSI_M, "n": kVK_ANSI_N, "o": kVK_ANSI_O, "p": kVK_ANSI_P, "q": kVK_ANSI_Q, "r": kVK_ANSI_R,
    "s": kVK_ANSI_S, "t": kVK_ANSI_T, "u": kVK_ANSI_U, "v": kVK_ANSI_V, "w": kVK_ANSI_W, "x": kVK_ANSI_X,
    "y": kVK_ANSI_Y, "z": kVK_ANSI_Z, "space": kVK_Space, "esc": kVK_Escape, "return": kVK_Return,
]

func key(_ arguments: [String]) {
    guard let combo = option("--combo", in: arguments) else { fail("key needs --combo") }
    var flags = CGEventFlags()
    var code: Int?
    for part in combo.lowercased().split(separator: "+").map(String.init) {
        switch part {
        case "ctrl", "control": flags.insert(.maskControl)
        case "opt", "option", "alt": flags.insert(.maskAlternate)
        case "cmd", "command": flags.insert(.maskCommand)
        case "shift": flags.insert(.maskShift)
        default: code = keyCodes[part]
        }
    }
    guard let code else { fail("unknown key in \(combo)") }
    let source = CGEventSource(stateID: .hidSystemState)
    let posted = Date().timeIntervalSince1970
    for down in [true, false] {
        guard let event = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(code), keyDown: down) else {
            fail("cannot create key event")
        }
        event.flags = flags
        event.post(tap: .cghidEventTap)
        usleep(20_000)
    }
    emit(["postedAt": posted])
}

// MARK: watch

func attribute(_ element: AXUIElement, _ name: String) -> CFTypeRef? {
    var value: CFTypeRef?
    return AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success ? value : nil
}

func text(of element: AXUIElement) -> String {
    for name in [kAXValueAttribute, kAXDescriptionAttribute, kAXTitleAttribute] {
        if let value = attribute(element, name as String) as? String, !value.isEmpty { return value }
    }
    return ""
}

/// Panel elements by identifier, searched breadth-first with a bound so a large window cannot stall a poll.
func panelElements(pid: pid_t) -> [String: AXUIElement] {
    let app = AXUIElementCreateApplication(pid)
    var queue = (attribute(app, kAXWindowsAttribute as String) as? [AXUIElement]) ?? []
    var found: [String: AXUIElement] = [:]
    var visited = 0
    while !queue.isEmpty, visited < 2_000 {
        let element = queue.removeFirst()
        visited += 1
        if let identifier = attribute(element, "AXIdentifier") as? String,
           identifier.hasPrefix("dictation-panel-"), found[identifier] == nil {
            found[identifier] = element
        }
        queue += (attribute(element, kAXChildrenAttribute as String) as? [AXUIElement]) ?? []
    }
    return found
}

func watch(_ arguments: [String]) {
    guard let pidText = option("--pid", in: arguments), let pid = pid_t(pidText),
          let path = option("--out", in: arguments) else { fail("watch needs --pid and --out") }
    let interval = Double(option("--interval", in: arguments) ?? "0.03") ?? 0.03
    FileManager.default.createFile(atPath: path, contents: nil, attributes: [.posixPermissions: 0o600])
    guard let handle = FileHandle(forWritingAtPath: path) else { fail("cannot write \(path)") }
    signal(SIGTERM) { _ in exit(0) }
    var last: [String: AnyHashable] = [:]
    while true {
        let elements = panelElements(pid: pid)
        var sample: [String: AnyHashable] = [
            "panel": !elements.isEmpty,
            "words": elements["dictation-panel-transcript"].map { wordCount(text(of: $0)) } ?? 0,
            "delivered": elements["dictation-panel-delivery-status"] != nil,
        ]
        // The state line is the app's own fixed copy, never dictated words.
        if let state = elements["dictation-panel-state"] { sample["state"] = text(of: state) }
        if sample != last {
            last = sample
            var line: [String: Any] = sample
            line["t"] = Date().timeIntervalSince1970
            emit(line, to: handle)
        }
        Thread.sleep(forTimeInterval: interval)
    }
}

// MARK: receiver

final class Receiver: NSObject, NSApplicationDelegate, NSTextStorageDelegate {
    let output: FileHandle
    let window = NSWindow(
        contentRect: NSRect(x: 200, y: 200, width: 520, height: 260),
        styleMask: [.titled], backing: .buffered, defer: false)
    let view = NSTextView(frame: NSRect(x: 0, y: 0, width: 520, height: 260))
    var signals: [DispatchSourceSignal] = []

    init(output: FileHandle) { self.output = output }

    func applicationDidFinishLaunching(_ notification: Notification) {
        window.title = "Spike receiver"
        view.textStorage?.delegate = self
        view.setAccessibilityIdentifier("spike-receiver-text")
        window.contentView = view
        let front = DispatchSource.makeSignalSource(signal: SIGUSR1, queue: .main)
        signal(SIGUSR1, SIG_IGN)
        front.setEventHandler { [weak self] in self?.bringForward(clearing: true) }
        front.resume()
        signals.append(front)
        bringForward(clearing: true)
        emit(["ready": true, "pid": ProcessInfo.processInfo.processIdentifier])
    }

    func bringForward(clearing: Bool) {
        if clearing { view.textStorage?.setAttributedString(NSAttributedString()) }
        window.makeKeyAndOrderFront(nil)
        window.makeFirstResponder(view)
        NSApp.activate(ignoringOtherApps: true)
    }

    func textStorage(
        _ textStorage: NSTextStorage, didProcessEditing editedMask: NSTextStorageEditActions,
        range editedRange: NSRange, changeInLength delta: Int
    ) {
        guard editedMask.contains(.editedCharacters), delta > 0 else { return }
        let inserted = (textStorage.string as NSString).substring(with: editedRange)
        emit(["t": Date().timeIntervalSince1970, "characters": delta, "words": wordCount(inserted)], to: output)
    }
}

func receive(_ arguments: [String]) {
    guard let path = option("--out", in: arguments) else { fail("receiver needs --out") }
    FileManager.default.createFile(atPath: path, contents: nil, attributes: [.posixPermissions: 0o600])
    guard let handle = FileHandle(forWritingAtPath: path) else { fail("cannot write \(path)") }
    handle.seekToEndOfFile()
    let app = NSApplication.shared
    let delegate = Receiver(output: handle)
    app.delegate = delegate
    app.setActivationPolicy(.regular)
    app.run()
}

let arguments = Array(CommandLine.arguments.dropFirst())
switch arguments.first {
case "check": check(arguments)
case "play": play(arguments)
case "key": key(arguments)
case "watch": watch(arguments)
case "receiver": receive(arguments)
default: fail("usage: spike-agent check|play|key|watch|receiver")
}

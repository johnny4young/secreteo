import AppKit
import ApplicationServices

// Launched with `open --args <probe|deliver> <result-path> [text] [receiver-bundle-id]`.
// Marker changes the binary, and so the cdhash, in the rebuild step.
let marker = "BUILD_MARKER"
let arguments = CommandLine.arguments
let resultPath = arguments[2]
var result: [String: Any] = [
    "marker": marker,
    "trusted": AXIsProcessTrusted(),
    "postEvent": CGPreflightPostEventAccess()
]

@MainActor
func finish() -> Never {
    let data = (try? JSONSerialization.data(withJSONObject: result, options: [.sortedKeys])) ?? Data()
    FileManager.default.createFile(atPath: resultPath, contents: data)
    exit(0)
}

guard arguments[1] == "deliver" else { finish() }

let text = arguments[3]
guard let receiver = NSRunningApplication.runningApplications(withBundleIdentifier: arguments[4]).first else {
    result["error"] = "receiver not running"
    finish()
}

NSPasteboard.general.clearContents()
NSPasteboard.general.setString(text, forType: .string)
receiver.activate()

let deadline = Date().addingTimeInterval(20)
while !receiver.isActive, Date() < deadline {
    RunLoop.current.run(until: Date().addingTimeInterval(0.1))
}
result["receiverActive"] = receiver.isActive

let source = CGEventSource(stateID: .combinedSessionState)
let keyV: CGKeyCode = 9
for down in [true, false] {
    let event = CGEvent(keyboardEventSource: source, virtualKey: keyV, keyDown: down)
    event?.flags = .maskCommand
    event?.post(tap: .cghidEventTap)
}
RunLoop.current.run(until: Date().addingTimeInterval(2))

let application = AXUIElementCreateApplication(receiver.processIdentifier)
var focused: CFTypeRef?
let focusStatus = AXUIElementCopyAttributeValue(application, kAXFocusedUIElementAttribute as CFString, &focused)
result["focusStatus"] = focusStatus.rawValue
if focusStatus == .success, let focused {
    var value: CFTypeRef?
    // swiftlint:disable:next force_cast
    let element = focused as! AXUIElement
    let valueStatus = AXUIElementCopyAttributeValue(element, kAXValueAttribute as CFString, &value)
    result["valueStatus"] = valueStatus.rawValue
    result["readback"] = value as? String ?? ""
}
finish()

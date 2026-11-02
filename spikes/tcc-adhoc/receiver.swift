import AppKit

// Launched with `open --args <record-path>`. Appends every text change to the record.
@MainActor
final class Receiver: NSObject, NSApplicationDelegate, NSTextViewDelegate {
    let recordPath: String
    let window = NSWindow(
        contentRect: NSRect(x: 200, y: 200, width: 480, height: 240),
        styleMask: [.titled], backing: .buffered, defer: false)
    let textView = NSTextView(frame: NSRect(x: 0, y: 0, width: 480, height: 240))

    init(recordPath: String) {
        self.recordPath = recordPath
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        textView.delegate = self
        window.contentView = textView
        window.makeFirstResponder(textView)
        window.makeKeyAndOrderFront(nil)
        NSApp.activate()
        FileManager.default.createFile(atPath: recordPath, contents: Data())
    }

    func textDidChange(_ notification: Notification) {
        FileManager.default.createFile(atPath: recordPath, contents: Data(textView.string.utf8))
    }
}

let application = NSApplication.shared
let delegate = MainActor.assumeIsolated { Receiver(recordPath: CommandLine.arguments[1]) }
application.delegate = delegate
application.setActivationPolicy(.regular)

let menu = NSMenu()
let appItem = NSMenuItem()
let editMenu = NSMenu(title: "Edit")
editMenu.addItem(NSMenuItem(title: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v"))
appItem.submenu = editMenu
menu.addItem(appItem)
application.mainMenu = menu

application.run()

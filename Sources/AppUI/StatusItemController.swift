import AppKit
import SwiftUI

/// An `NSStatusItem` rather than `MenuBarExtra`, whose scene can stay registered on
/// macOS 26 without painting. There is no autosave name, because saved customization
/// is what can keep a hidden item registered.
@MainActor
public final class StatusItemController: NSObject {
    private let model: AppModel
    private var statusItem: NSStatusItem?
    private let popover = NSPopover()
    private let focusReturn = MenuFocusReturn()

    public init(model: AppModel) {
        self.model = model
        super.init()
        popover.behavior = .transient
        let content = MenuContentView(model: model) { [weak self] action in
            self?.popover.performClose(nil)
            self?.focusReturn.run(action)
        }
        popover.contentViewController = NSHostingController(rootView: content)
    }

    /// False once macOS or the user removes the icon.
    public var hasVisibleAffordance: Bool {
        guard let statusItem, statusItem.isVisible else { return false }
        return statusItem.button?.window != nil
    }

    public func attach() {
        guard statusItem == nil else { return }
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        // Dragging the icon out of the menu bar quits the app.
        item.behavior = .terminationOnRemoval
        item.button?.image = NSImage(systemSymbolName: "waveform", accessibilityDescription: "Secreteo")
        item.button?.image?.isTemplate = true
        item.button?.target = self
        item.button?.action = #selector(togglePopover)
        item.isVisible = true
        statusItem = item
    }

    public func closeMenu() {
        popover.performClose(nil)
    }

    @objc private func togglePopover() {
        guard let button = statusItem?.button else { return }
        if popover.isShown {
            popover.performClose(nil)
        } else {
            focusReturn.remember()
            NSApp.activate()
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        }
    }
}

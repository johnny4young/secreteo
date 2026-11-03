import AppKit

/// The main menu of an agent app is never shown. It exists for its key equivalents.
@MainActor
enum StandardMenu {
    static func make() -> NSMenu {
        let menu = NSMenu()
        menu.addItem(submenu(
            title: "Secreteo",
            items: [item(String(localized: "Quit Secreteo"), #selector(NSApplication.terminate(_:)), "q")]))
        menu.addItem(submenu(
            title: String(localized: "Edit"),
            items: [
                item(String(localized: "Undo"), Selector(("undo:")), "z"),
                item(String(localized: "Cut"), #selector(NSText.cut(_:)), "x"),
                item(String(localized: "Copy"), #selector(NSText.copy(_:)), "c"),
                item(String(localized: "Paste"), #selector(NSText.paste(_:)), "v"),
                item(String(localized: "Select All"), #selector(NSText.selectAll(_:)), "a")
            ]))
        menu.addItem(submenu(
            title: String(localized: "Window"),
            items: [item(String(localized: "Close"), #selector(NSWindow.performClose(_:)), "w")]))
        return menu
    }

    private static func item(_ title: String, _ action: Selector, _ key: String) -> NSMenuItem {
        NSMenuItem(title: title, action: action, keyEquivalent: key)
    }

    private static func submenu(title: String, items: [NSMenuItem]) -> NSMenuItem {
        let holder = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        let submenu = NSMenu(title: title)
        items.forEach(submenu.addItem)
        holder.submenu = submenu
        return holder
    }
}

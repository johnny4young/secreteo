import Carbon.HIToolbox

/// Optional fixed shortcut for pasting the last dictation; off by default.
/// ⌥⌘V and ⇧⌥⌘V already mean "move" and "paste and match style" in many apps.
enum PasteLastShortcut {
    static let defaultsKey = "dictationPasteLastHotkey"
    static let setting = HotkeySetting(
        keyCode: UInt32(kVK_ANSI_V), modifiers: UInt32(controlKey | optionKey | cmdKey), label: "⌃⌥⌘V")
}

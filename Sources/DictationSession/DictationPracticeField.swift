import AppKit
import Observation
import DictationKit

/// An in-app field for trying dictation with the real microphone and model.
/// While its window is the key window, a new session delivers here: no
/// clipboard, no synthetic paste and no Accessibility.
@MainActor
@Observable
final class DictationPracticeField {
    private(set) var text = ""
    /// Each visible field and whether its window is key.
    @ObservationIgnored private var holders: [UUID: Bool] = [:]
    /// Runs when the words go, so they leave wherever else they are held.
    @ObservationIgnored var onForget: (() -> Void)?

    /// Completion is a local boolean; the delivered words never enter preferences.
    @ObservationIgnored var onVerifiedDelivery: (() -> Void)?

    var isArmed: Bool { holders.values.contains(true) }

    func show(_ holder: UUID, isKey: Bool) {
        holders[holder] = isKey
    }

    /// Practice text is never kept once no view shows the field.
    func hide(_ holder: UUID) {
        holders[holder] = nil
        if holders.isEmpty { clear() }
    }

    func clear() {
        text = ""
        onForget?()
    }

    func receive(_ dictated: String) -> DictationDeliveryOutcome {
        let words = dictated.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !words.isEmpty else { return .refused(.emptyText) }
        guard !holders.isEmpty else { return .refused(.targetChanged) }
        text = text.isEmpty ? words : text + " " + words
        onVerifiedDelivery?()
        return .verified
    }

    /// The destination is chosen when a session starts, so a session begun in
    /// another app keeps that app's field even if the practice field appears later.
    func route(
        _ dependencies: DictationSessionDependencies, appIsActive: Bool,
        isStillShown: @escaping () -> Bool = { true }
    ) -> DictationSessionDependencies {
        guard isArmed, appIsActive else { return dependencies }
        var routed = dependencies
        routed.admissionKind = .practice
        routed.canInsert = { true }
        routed.beginHistory = { nil }
        routed.recordStats = { _ in }
        routed.locatePanelAnchor = { Self.panelAnchor(around: NSEvent.mouseLocation) }
        routed.captureDestination = { [weak self] in
            CapturedDictationDestination(name: L10n.text("the practice field"), canRetry: false) { text in
                guard isStillShown() else { return .refused(.targetChanged) }
                return self?.receive(text) ?? .refused(.targetChanged)
            }
        }
        return routed
    }

    /// The field has no caret, so the strip opens by the pointer that started the
    /// session, above or below, without covering the button under it.
    static func panelAnchor(around point: NSPoint) -> DictationPanelAnchor {
        .caret(NSRect(x: point.x, y: point.y - 24, width: 0, height: 48))
    }
}

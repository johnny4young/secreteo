import Foundation

extension DictationFeature {
    /// A disposable launch has its own fixtures, so it needs no model.
    var canPractice: Bool { environment.models == nil || speechModelIsInstalled || !speechModelIsRequired }
    var practiceIsShown: Bool { isEnabled && canPractice }

    /// The window holds the practice field, because the form's rows come and go as it scrolls.
    public func practiceWindowChanged(_ holder: UUID, isKey: Bool) {
        practice.show(holder, isKey: isKey)
    }

    public func practiceWindowClosed(_ holder: UUID) {
        practice.hide(holder)
    }

    public func settingsWindowChanged(isKey: Bool) {
        practiceWindowChanged(settingsWindowHolder, isKey: isKey)
        // Coming back from System Settings › Keyboard is the moment the 🌐 choice may have changed.
        if isKey { refreshFnKey() }
    }

    public func settingsWindowClosed() {
        practiceWindowClosed(settingsWindowHolder)
    }
}

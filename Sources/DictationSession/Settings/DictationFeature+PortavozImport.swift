import Foundation

extension DictationFeature {
    func refreshPortavozImport() {
        let found = PortavozPreferenceImport(portavoz: environment.portavozPreferences(), current: defaults)
        portavozImport = found.changes.isEmpty ? nil : found
    }

    func importPortavozPreferences() {
        guard let portavozImport else { return }
        store(portavozImport.values)
        textSettingsIfCreated?.reload()
        if portavozImport.values[LiveSpeechSelection.dictationKey] != nil { speechEngineChanged() }
        modelMemoryChanged()
        refreshPortavozImport()
    }
}

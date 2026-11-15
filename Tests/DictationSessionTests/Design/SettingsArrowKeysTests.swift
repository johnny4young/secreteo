import Testing

@testable import DictationSession

struct SettingsArrowKeysTests {
    @Test func arrowsMoveOneChoiceAndStopAtEitherEnd() {
        let tabs = SettingsTab.allCases
        #expect(SettingsArrowKeys.neighbor(of: .text, in: tabs, by: 1) == .polish)
        #expect(SettingsArrowKeys.neighbor(of: .text, in: tabs, by: -1) == .dictation)
        #expect(SettingsArrowKeys.neighbor(of: .dictation, in: tabs, by: -1) == .dictation)
        #expect(SettingsArrowKeys.neighbor(of: .general, in: tabs, by: 1) == .general)
    }

    @Test func aChoiceThatIsNotOfferedStaysAsItIs() {
        #expect(SettingsArrowKeys.neighbor(of: SettingsTab.text, in: [.dictation, .history, .general], by: 1) == .text)
        #expect(SettingsArrowKeys.neighbor(of: SettingsTab.text, in: [], by: 1) == .text)
    }
}

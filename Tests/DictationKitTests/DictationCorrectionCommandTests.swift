import DictationKit
import Foundation
import Testing

struct DictationCorrectionCommandTests {
    @Test(arguments: [
        ("Change Friday to Monday.", DictationCorrectionCommand.replace("Friday", with: "Monday")),
        ("replace the draft with the final version", .replace("the draft", with: "the final version")),
        ("Cambia viernes por lunes.", .replace("viernes", with: "lunes")),
        ("reemplaza borrador por versión final", .replace("borrador", with: "versión final")),
        ("Delete Friday", .delete("Friday")),
        ("borra viernes", .delete("viernes")),
        ("Scratch that.", .deleteLast),
        ("borra eso", .deleteLast),
        ("Bórralo", .deleteLast)
    ])
    func spokenCommandsParseInEnglishAndSpanish(_ example: (String, DictationCorrectionCommand)) {
        #expect(DictationCorrectionCommand.parse(example.0) == example.1)
    }

    @Test(arguments: ["Let's meet on Friday", "No borres estas notas", "", "change"])
    func ordinaryDictationIsNotACommand(_ text: String) {
        #expect(DictationCorrectionCommand.parse(text) == nil)
    }

    @Test
    func aCommandAppliesOnlyToWhatTheInsertionContains() {
        let inserted = "Ship it on Friday, then tell Ana on Friday evening."
        let edit = DictationCorrectionCommand.replace("friday", with: "monday").edit(in: inserted)
        #expect(edit?.range == (inserted as NSString).range(of: "Friday", options: .backwards))
        #expect(edit?.replacement == "Monday")
        #expect(DictationCorrectionCommand.replace("of plans", with: "monday").edit(in: inserted) == nil)
        #expect(DictationCorrectionCommand.replace("Fri", with: "Mon").edit(in: inserted) == nil)
        let deletion = DictationCorrectionCommand.delete("then").edit(in: inserted)
        #expect(deletion?.range == (inserted as NSString).range(of: "then "))
        #expect(DictationCorrectionCommand.deleteLast.edit(in: inserted)?.range
            == NSRange(location: 0, length: inserted.utf16.count))
    }
}

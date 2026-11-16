import AppKit
import Foundation
import Testing

@testable import DictationSession

struct SecreteoDesignTests {
    private static let repository = DictationModelFixture.root

    @Test
    func amberMatchesPortavozExactly() {
        #expect(SecreteoPalette.amber == SecreteoColor(light: 0xE9A318, dark: 0xF4B63C))
    }

    @Test(arguments: [
        ("text on paper", SecreteoPalette.text.light, SecreteoPalette.window.light),
        ("secondary on paper", SecreteoPalette.secondaryText.light, SecreteoPalette.window.light),
        ("tertiary on paper", SecreteoPalette.tertiaryText.light, SecreteoPalette.window.light),
        ("accent on paper", SecreteoPalette.accent.light, SecreteoPalette.window.light),
        ("verified on paper", SecreteoPalette.verified.light, SecreteoPalette.window.light),
        ("not sent on paper", SecreteoPalette.notSent.light, SecreteoPalette.window.light),
        ("text on dark", SecreteoPalette.text.dark, SecreteoPalette.window.dark),
        ("secondary on dark", SecreteoPalette.secondaryText.dark, SecreteoPalette.window.dark),
        ("tertiary on dark", SecreteoPalette.tertiaryText.dark, SecreteoPalette.window.dark),
        ("accent on dark", SecreteoPalette.accent.dark, SecreteoPalette.window.dark),
        ("verified on dark", SecreteoPalette.verified.dark, SecreteoPalette.window.dark),
        ("not sent on dark", SecreteoPalette.notSent.dark, SecreteoPalette.window.dark),
        ("capsule text", SecreteoPalette.capsuleText.light, SecreteoPalette.lacquer.light),
        ("capsule secondary", SecreteoPalette.capsuleSecondaryText.light, SecreteoPalette.lacquer.light),
        ("capsule tertiary", SecreteoPalette.capsuleTertiaryText.light, SecreteoPalette.lacquer.light),
        ("primary button top", SecreteoPalette.capsulePrimaryText.light, SecreteoPalette.capsulePrimaryTop.light),
        ("primary button bottom", SecreteoPalette.capsulePrimaryText.light, SecreteoPalette.capsulePrimaryBottom.light),
        ("capsule accent", SecreteoPalette.capsuleAccent.light, SecreteoPalette.lacquer.light),
        ("capsule verified", SecreteoPalette.capsuleVerified.light, SecreteoPalette.lacquer.light),
        ("capsule not sent", SecreteoPalette.capsuleNotSent.light, SecreteoPalette.lacquer.light),
        ("amber on capsule", SecreteoPalette.amber.dark, SecreteoPalette.lacquer.light),
        ("white on accent", 0xFFFFFF, SecreteoPalette.accent.light),
        ("text on card", SecreteoPalette.text.light, SecreteoPalette.card.light),
        ("secondary on card", SecreteoPalette.secondaryText.light, SecreteoPalette.card.light),
        ("tertiary on card", SecreteoPalette.tertiaryText.light, SecreteoPalette.card.light),
        ("accent on card", SecreteoPalette.accent.light, SecreteoPalette.card.light),
        ("not sent on card", SecreteoPalette.notSent.light, SecreteoPalette.card.light),
        ("verified on card", SecreteoPalette.verified.light, SecreteoPalette.card.light),
        ("text on dark card", SecreteoPalette.text.dark, SecreteoPalette.card.dark),
        ("secondary on dark card", SecreteoPalette.secondaryText.dark, SecreteoPalette.card.dark),
        ("tertiary on dark card", SecreteoPalette.tertiaryText.dark, SecreteoPalette.card.dark),
        ("accent on dark card", SecreteoPalette.accent.dark, SecreteoPalette.card.dark),
        ("not sent on dark card", SecreteoPalette.notSent.dark, SecreteoPalette.card.dark),
        ("verified on dark card", SecreteoPalette.verified.dark, SecreteoPalette.card.dark),
        ("secondary on bar", SecreteoPalette.secondaryText.light, SecreteoPalette.bar.light),
        ("accent on bar", SecreteoPalette.accent.light, SecreteoPalette.bar.light),
        ("secondary on dark bar", SecreteoPalette.secondaryText.dark, SecreteoPalette.bar.dark),
        ("accent on dark bar", SecreteoPalette.accent.dark, SecreteoPalette.bar.dark),
        ("secondary on control", SecreteoPalette.secondaryText.light, SecreteoPalette.control.light),
        ("tertiary on control", SecreteoPalette.tertiaryText.light, SecreteoPalette.control.light),
        ("secondary on dark control", SecreteoPalette.secondaryText.dark, SecreteoPalette.control.dark),
        ("tertiary on dark control", SecreteoPalette.tertiaryText.dark, SecreteoPalette.control.dark),
        ("segment text", SecreteoPalette.segmentText.light, SecreteoPalette.segment.light),
        ("dark segment text", SecreteoPalette.segmentText.dark, SecreteoPalette.segment.dark),
        ("text on amber", SecreteoPalette.onAmber.light, SecreteoPalette.amber.light),
        ("text on dark amber", SecreteoPalette.onAmber.dark, SecreteoPalette.amber.dark),
        ("row text on accent", SecreteoPalette.onAccent.light, SecreteoPalette.accent.light),
        ("row text on dark accent", SecreteoPalette.onAccent.dark, SecreteoPalette.accent.dark),
        ("capsule text on its highlight", SecreteoPalette.capsuleText.light, SecreteoPalette.capsuleHighlight.light),
        ("capsule secondary on its highlight", SecreteoPalette.capsuleSecondaryText.light,
         SecreteoPalette.capsuleHighlight.light),
        ("ink on an amber key", SecreteoPalette.capsuleInk.light, SecreteoPalette.capsuleAmber.light),
        ("ink on a copper button", SecreteoPalette.capsuleInk.light, SecreteoPalette.capsuleAccent.light),
        ("text on a card", SecreteoPalette.text.light, SecreteoPalette.card.light),
        ("secondary on a card", SecreteoPalette.secondaryText.light, SecreteoPalette.card.light),
        ("tertiary on a card", SecreteoPalette.tertiaryText.light, SecreteoPalette.card.light),
        ("accent on a card", SecreteoPalette.accent.light, SecreteoPalette.card.light),
        ("text on a dark card", SecreteoPalette.text.dark, SecreteoPalette.card.dark),
        ("secondary on a dark card", SecreteoPalette.secondaryText.dark, SecreteoPalette.card.dark),
        ("tertiary on a dark card", SecreteoPalette.tertiaryText.dark, SecreteoPalette.card.dark),
        ("accent on a dark card", SecreteoPalette.accent.dark, SecreteoPalette.card.dark),
        ("text on card, light", SecreteoPalette.text.light, SecreteoPalette.card.light),
        ("text on card, dark", SecreteoPalette.text.dark, SecreteoPalette.card.dark),
        ("text on field, light", SecreteoPalette.text.light, SecreteoPalette.field.light),
        ("text on field, dark", SecreteoPalette.text.dark, SecreteoPalette.field.dark),
        ("secondary on card, light", SecreteoPalette.secondaryText.light, SecreteoPalette.card.light),
        ("secondary on card, dark", SecreteoPalette.secondaryText.dark, SecreteoPalette.card.dark),
        ("secondary on field, light", SecreteoPalette.secondaryText.light, SecreteoPalette.field.light),
        ("secondary on field, dark", SecreteoPalette.secondaryText.dark, SecreteoPalette.field.dark),
        ("tertiary on card, light", SecreteoPalette.tertiaryText.light, SecreteoPalette.card.light),
        ("tertiary on card, dark", SecreteoPalette.tertiaryText.dark, SecreteoPalette.card.dark),
        ("tertiary on field, light", SecreteoPalette.tertiaryText.light, SecreteoPalette.field.light),
        ("tertiary on field, dark", SecreteoPalette.tertiaryText.dark, SecreteoPalette.field.dark),
        ("accent on card, light", SecreteoPalette.accent.light, SecreteoPalette.card.light),
        ("accent on card, dark", SecreteoPalette.accent.dark, SecreteoPalette.card.dark),
        ("not sent on card, light", SecreteoPalette.notSent.light, SecreteoPalette.card.light),
        ("not sent on card, dark", SecreteoPalette.notSent.dark, SecreteoPalette.card.dark),
        ("white on accent", 0xFFFFFF, SecreteoPalette.accent.light),
        ("indicator stroke on its outline", SecreteoPalette.capsuleText.light, SecreteoPalette.asideOutline.light),
        ("indicator amber on its outline", SecreteoPalette.capsuleAmber.light, SecreteoPalette.asideOutline.light),
        ("indicator verified on its outline", SecreteoPalette.capsuleVerified.light, SecreteoPalette.asideOutline.light),
        ("indicator not sent on its outline", SecreteoPalette.capsuleNotSent.light, SecreteoPalette.asideOutline.light),
        ("indicator no speech on its outline", SecreteoPalette.asideQuiet.light, SecreteoPalette.asideOutline.light)
    ] as [(String, UInt32, UInt32)])
    func textMeetsContrast(_ pair: (String, UInt32, UInt32)) {
        #expect(Self.contrast(pair.1, pair.2) >= 4.5, "\(pair.0)")
    }

    @Test(arguments: [
        ("bar, light", SecreteoPalette.dayBar.light, SecreteoPalette.card.light),
        ("bar, dark", SecreteoPalette.dayBar.dark, SecreteoPalette.card.dark),
        ("empty bar, light", SecreteoPalette.emptyBar.light, SecreteoPalette.card.light),
        ("empty bar, dark", SecreteoPalette.emptyBar.dark, SecreteoPalette.card.dark),
        ("today's bar, light", SecreteoPalette.todayBar.light, SecreteoPalette.card.light),
        ("today's bar, dark", SecreteoPalette.todayBar.dark, SecreteoPalette.card.dark)
    ] as [(String, UInt32, UInt32)])
    func chartMarksMeetGraphicContrast(_ pair: (String, UInt32, UInt32)) {
        #expect(Self.contrast(pair.1, pair.2) >= 3, "\(pair.0)")
    }

    @Test
    func dynamicColorsFollowTheAppearance() throws {
        let color = SecreteoPalette.accent.nsColor
        var light = NSColor.clear, dark = NSColor.clear
        NSAppearance(named: .aqua)?.performAsCurrentDrawingAppearance { light = color.usingColorSpace(.sRGB)! }
        NSAppearance(named: .darkAqua)?.performAsCurrentDrawingAppearance { dark = color.usingColorSpace(.sRGB)! }
        #expect(Int((light.redComponent * 255).rounded()) == 0x9A)
        #expect(Int((dark.redComponent * 255).rounded()) == 0xE8)
    }

    @Test
    func theSerifFontShipsInTheFolderTheAppRegisters() throws {
        let plist = try String(contentsOf: Self.repository.appending(path: "Apps/Secreteo/Info.plist"), encoding: .utf8)
        #expect(plist.contains("<key>ATSApplicationFontsPath</key>\n\t<string>Fonts</string>"))
        let fonts = Self.repository.appending(path: "Apps/Secreteo/Resources/Fonts")
        for name in [SecreteoSerif.regularName, SecreteoSerif.italicName] {
            let url = fonts.appending(path: "\(name).ttf")
            let descriptors = try #require(CTFontManagerCreateFontDescriptorsFromURL(url as CFURL) as? [CTFontDescriptor])
            let postScript = descriptors.compactMap { CTFontDescriptorCopyAttribute($0, kCTFontNameAttribute) as? String }
            #expect(postScript == [name])
        }
        let notices = try String(contentsOf: Self.repository.appending(path: "THIRD-PARTY-NOTICES.md"), encoding: .utf8)
        #expect(notices.contains("## Instrument Serif"))
        #expect(notices.contains("SIL OPEN FONT LICENSE Version 1.1"))
    }

    private static func contrast(_ foreground: UInt32, _ background: UInt32) -> Double {
        let lighter = max(luminance(foreground), luminance(background))
        let darker = min(luminance(foreground), luminance(background))
        return (lighter + 0.05) / (darker + 0.05)
    }

    private static func luminance(_ hex: UInt32) -> Double {
        func channel(_ shift: UInt32) -> Double {
            let value = Double((hex >> shift) & 0xFF) / 255
            return value <= 0.04045 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * channel(16) + 0.7152 * channel(8) + 0.0722 * channel(0)
    }
}

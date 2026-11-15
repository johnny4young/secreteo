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
        ("capsule accent", SecreteoPalette.capsuleAccent.light, SecreteoPalette.lacquer.light),
        ("capsule verified", SecreteoPalette.capsuleVerified.light, SecreteoPalette.lacquer.light),
        ("capsule not sent", SecreteoPalette.capsuleNotSent.light, SecreteoPalette.lacquer.light),
        ("amber on capsule", SecreteoPalette.amber.dark, SecreteoPalette.lacquer.light),
        ("white on accent", 0xFFFFFF, SecreteoPalette.accent.light)
    ] as [(String, UInt32, UInt32)])
    func textMeetsContrast(_ pair: (String, UInt32, UInt32)) {
        #expect(Self.contrast(pair.1, pair.2) >= 4.5, "\(pair.0)")
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

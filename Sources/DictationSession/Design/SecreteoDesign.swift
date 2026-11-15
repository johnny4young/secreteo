import AppKit
import SwiftUI

/// One sRGB colour with its light and dark values, kept as numbers so tests can check contrast.
public struct SecreteoColor: Sendable, Equatable {
    public let light: UInt32
    public let dark: UInt32

    init(light: UInt32, dark: UInt32) {
        self.light = light
        self.dark = dark
    }

    init(_ both: UInt32) {
        self.init(light: both, dark: both)
    }

    public var nsColor: NSColor {
        let light = light, dark = dark
        if light == dark { return Self.make(light) }
        return NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? Self.make(dark) : Self.make(light)
        }
    }

    public var color: Color { Color(nsColor: nsColor) }

    static func make(_ hex: UInt32) -> NSColor {
        NSColor(
            srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
    }
}

/// The Brasa palette: copper for the product, amber for you, on warm paper or lacquer.
public enum SecreteoPalette {
    /// Buttons, links and selection.
    public static let accent = SecreteoColor(light: 0x9A4A1F, dark: 0xE8936A)
    /// Your voice and your caret. The same values as Portavoz.
    public static let amber = SecreteoColor(light: 0xE9A318, dark: 0xF4B63C)
    /// The voice light and the capsule rim. Never text.
    public static let ember = SecreteoColor(0xF0703A)
    public static let verified = SecreteoColor(light: 0x1F6F5C, dark: 0x7FD1B9)
    public static let notSent = SecreteoColor(light: 0xB93A22, dark: 0xFF8D73)
    public static let lacquer = SecreteoColor(0x15100D)
    public static let paper = SecreteoColor(0xFBF7F2)
    public static let window = SecreteoColor(light: 0xFBF7F2, dark: 0x1B120E)
    public static let text = SecreteoColor(light: 0x1E1612, dark: 0xFBF1E6)
    public static let secondaryText = SecreteoColor(light: 0x5F4F44, dark: 0xCDB9A8)
    public static let tertiaryText = SecreteoColor(light: 0x7A685B, dark: 0xA08C7C)
    public static let card = SecreteoColor(light: 0xFFFFFF, dark: 0x261C17)
    /// The Settings tab bar, and the well behind a picker or a segment.
    public static let bar = SecreteoColor(light: 0xF4ECE3, dark: 0x231A15)
    public static let control = SecreteoColor(light: 0xF4ECE3, dark: 0x33261F)
    public static let segment = SecreteoColor(light: 0xFFFFFF, dark: 0xE8936A)
    public static let segmentText = SecreteoColor(light: 0x1E1612, dark: 0x2A1206)
    public static let onAmber = SecreteoColor(0x2A1206)
    public static let keyCap = SecreteoColor(light: 0xFFFFFF, dark: 0x33261F)
    /// Text on the always-dark capsule, whatever the system appearance.
    public static let capsuleText = SecreteoColor(0xFBF1E6)
    public static let capsuleSecondaryText = SecreteoColor(0xCDB9A8)
    public static let capsuleVerified = SecreteoColor(0x7FD1B9)
    public static let capsuleNotSent = SecreteoColor(0xFF8D73)
    public static let capsuleAccent = SecreteoColor(0xE8936A)
}

public enum SecreteoDesign {
    public static let accent = SecreteoPalette.accent.color
    public static let amber = SecreteoPalette.amber.color
    public static let ember = SecreteoPalette.ember.color
    public static let verified = SecreteoPalette.verified.color
    public static let notSent = SecreteoPalette.notSent.color
    public static let windowBackground = SecreteoPalette.window.color
    public static let secondaryText = SecreteoPalette.secondaryText.color
    public static let tertiaryText = SecreteoPalette.tertiaryText.color
    public static let card = SecreteoPalette.card.color
    public static let settingsBar = SecreteoPalette.bar.color
    public static let control = SecreteoPalette.control.color
    public static let segment = SecreteoPalette.segment.color
    public static let segmentText = SecreteoPalette.segmentText.color
    public static let onAmber = SecreteoPalette.onAmber.color
    public static let keyCap = SecreteoPalette.keyCap.color
    public static let hairline = SecreteoPalette.text.color.opacity(0.1)
    public static let keyEdge = SecreteoPalette.text.color.opacity(0.18)
    public static let accentWash = SecreteoPalette.accent.color.opacity(0.1)
}

/// Instrument Serif for titles, numerals and provisional words; New York when the font did not register.
public enum SecreteoSerif {
    static let regularName = "InstrumentSerif-Regular"
    static let italicName = "InstrumentSerif-Italic"

    /// Registration lasts for the process, so one lookup answers every render.
    public static let isBundledFontAvailable =
        NSFont(name: regularName, size: 12) != nil && NSFont(name: italicName, size: 12) != nil

    public static func font(size: CGFloat, italic: Bool = false) -> Font {
        if isBundledFontAvailable {
            return .custom(italic ? italicName : regularName, fixedSize: size)
        }
        let fallback = Font.system(size: size, design: .serif)
        return italic ? fallback.italic() : fallback
    }
}

extension Font {
    public static func secreteoSerif(_ size: CGFloat, italic: Bool = false) -> Font {
        SecreteoSerif.font(size: size, italic: italic)
    }
}

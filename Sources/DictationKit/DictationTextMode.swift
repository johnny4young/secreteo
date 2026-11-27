/// A post-recognition choice. Literal and clean are deterministic; polish is the one
/// generative mode, chosen explicitly, and always starts from the clean text.
public enum DictationTextMode: String, Codable, CaseIterable, Sendable {
    case literal
    case clean
    case polish

    /// Polish runs the clean rules first, so the deterministic tier applies to both.
    public var appliesCleanRules: Bool { self != .literal }
}

/// Only application identity is durable; window titles, URLs and editor contents are not profiles.
public struct DictationApplicationTextProfile: Codable, Equatable, Identifiable, Sendable {
    public let bundleIdentifier: String
    public var mode: DictationTextMode
    /// The Polish recipe for this application; nil is the conservative copy edit.
    public var polishRecipeID: String?
    /// Nil follows the default translation; `.off` keeps this application untranslated.
    public var translationTarget: DictationTranslationTarget?
    /// When true (Code / Terminal preset), preserves camelCase, snake_case, CLI flags,
    /// and skips cursor recasing so shell commands and identifiers stay verbatim.
    public var preservesCodeTokens: Bool?
    public var id: String { bundleIdentifier }
    public var keepsCodeTokens: Bool { preservesCodeTokens == true }

    public init(
        bundleIdentifier: String, mode: DictationTextMode, polishRecipeID: String? = nil,
        translationTarget: DictationTranslationTarget? = nil,
        preservesCodeTokens: Bool? = nil
    ) {
        self.bundleIdentifier = bundleIdentifier
        self.mode = mode
        self.polishRecipeID = mode == .polish ? polishRecipeID : nil
        self.translationTarget = translationTarget
        self.preservesCodeTokens = preservesCodeTokens == true ? true : nil
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let bundleIdentifier = try container.decode(String.self, forKey: .bundleIdentifier)
        let mode = try container.decode(DictationTextMode.self, forKey: .mode)
        let polishRecipeID = try container.decodeIfPresent(String.self, forKey: .polishRecipeID)
        let translationTarget = try container.decodeIfPresent(
            DictationTranslationTarget.self, forKey: .translationTarget)
        let preservesCodeTokens = try container.decodeIfPresent(Bool.self, forKey: .preservesCodeTokens)
        self.init(
            bundleIdentifier: bundleIdentifier,
            mode: mode,
            polishRecipeID: polishRecipeID,
            translationTarget: translationTarget,
            preservesCodeTokens: preservesCodeTokens)
    }

    public var choice: DictationTextChoice { DictationTextChoice(mode: mode, recipeID: polishRecipeID) }
}

/// Curated application profile presets so users can configure Chat, Email, and
/// Code / Terminal apps in one click without picking raw modes per app.
public enum DictationProfilePreset: String, CaseIterable, Identifiable, Sendable {
    case chat
    case email
    case code

    public var id: String { rawValue }

    public var mode: DictationTextMode {
        switch self {
        case .chat, .code: .clean
        case .email: .polish
        }
    }

    public var polishRecipeID: String? {
        switch self {
        case .chat, .code: nil
        case .email: "builtin.formal"
        }
    }

    public var preservesCodeTokens: Bool { self == .code }

    public var choice: DictationTextChoice { DictationTextChoice(mode: mode, recipeID: polishRecipeID) }

    public var bundleIdentifiers: [String] {
        switch self {
        case .chat:
            [
                "com.tinyspeck.slackmacgap",
                "com.hnc.Discord",
                "com.apple.MobileSMS",
                "net.whatsapp.WhatsApp",
                "ru.keepcoder.Telegram",
                "com.microsoft.teams2"
            ]
        case .email:
            [
                "com.apple.mail",
                "com.readdle.SparkDesktop",
                "com.readdle.smartemail-Mac",
                "com.mimestream.Mimestream",
                "com.microsoft.Outlook",
                "org.mozilla.thunderbird"
            ]
        case .code:
            [
                "com.apple.dt.Xcode",
                "com.apple.Terminal",
                "com.googlecode.iterm2",
                "com.mitchellh.ghostty",
                "dev.warp.Warp-Stable",
                "com.microsoft.VSCode",
                "com.todesktop.230313mzl4w4u92",
                "dev.zed.Zed",
                "com.google.antigravity"
            ]
        }
    }

    public static func suggested(for bundleIdentifier: String) -> Self? {
        allCases.first { $0.bundleIdentifiers.contains(bundleIdentifier) }
    }

    public func makeProfile(bundleIdentifier: String) -> DictationApplicationTextProfile {
        DictationApplicationTextProfile(
            bundleIdentifier: bundleIdentifier,
            mode: mode,
            polishRecipeID: polishRecipeID,
            preservesCodeTokens: preservesCodeTokens ? true : nil)
    }
}

/// Where dictated text is translated before it is pasted. Off and the two recognized languages only.
public enum DictationTranslationTarget: String, Codable, CaseIterable, Sendable {
    case off
    case english = "en"
    case spanish = "es"

    /// The BCP-47 language the translator produces, or nil when off.
    public var languageCode: String? { self == .off ? nil : rawValue }
}

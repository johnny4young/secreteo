import AppKit
import SwiftUI

/// The one accent of the product.
enum SecreteoDesign {
    static let accent = Color.indigo
}

enum SecreteoSymbol {
    static let success = "checkmark.circle.fill"
}

enum UITestWindowPlacement {
    static func floatingPanelLevel() -> NSWindow.Level { .floating }
}

private struct AppLocaleModifier: ViewModifier {
    @AppStorage(AppLanguage.storageKey) private var appLanguageRaw = AppLanguage.system.rawValue

    func body(content: Content) -> some View {
        content.environment(\.locale, AppLanguage.fromStorage(appLanguageRaw).locale)
    }
}

extension View {
    func secreteoLocalized() -> some View {
        modifier(AppLocaleModifier())
    }
}

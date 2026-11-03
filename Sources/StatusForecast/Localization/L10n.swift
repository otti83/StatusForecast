import Foundation
import SwiftUI
import AppKit

/// Override-aware locale + sub-bundle. Updated from the main actor whenever
/// `Preferences.languageOverride` changes; read from anywhere.
enum LocaleProvider {
    // Installed .app bundles store SwiftPM resources in Contents/Resources.
    // Keep SwiftPM's accessor as a lazy fallback for `swift run`.
    private static let resourceBundle: Bundle = {
        if let url = Bundle.main.resourceURL?.appendingPathComponent("StatusForecast_StatusForecast.bundle"),
           let bundle = Bundle(url: url) {
            return bundle
        }
        return .module
    }()

    nonisolated(unsafe) static private(set) var currentLocale: Locale = .autoupdatingCurrent
    nonisolated(unsafe) static private(set) var currentBundle: Bundle = resourceBundle

    static func apply(_ override: LanguageOverride) {
        let lang: String
        switch override {
        case .system:
            // Pick from system preferred languages, falling back to English.
            let sys = Locale.preferredLanguages.first ?? "en"
            lang = sys.hasPrefix("ja") ? "ja" : "en"
            currentLocale = Locale.autoupdatingCurrent
        case .en:
            lang = "en"
            currentLocale = Locale(identifier: "en")
        case .ja:
            lang = "ja"
            currentLocale = Locale(identifier: "ja")
        }
        // Always go through the explicit lproj sub-bundle — Bundle.module's
        // own preferredLocalizations resolution has been unreliable across
        // SPM resource-bundle layout changes.
        currentBundle = subBundle(lang) ?? resourceBundle
    }

    private static func subBundle(_ code: String) -> Bundle? {
        guard let path = resourceBundle.path(forResource: code, ofType: "lproj"),
              let b = Bundle(path: path) else { return nil }
        return b
    }
}

enum L10n {
    static func t(_ key: String) -> String {
        NSLocalizedString(key, tableName: nil, bundle: LocaleProvider.currentBundle, value: key, comment: "")
    }

    static func tf(_ key: String, _ args: CVarArg...) -> String {
        let fmt = NSLocalizedString(key, tableName: nil, bundle: LocaleProvider.currentBundle, value: key, comment: "")
        return String(format: fmt, locale: LocaleProvider.currentLocale, arguments: args)
    }
}

/// SwiftUI shortcut. Reads through `LocaleProvider.currentBundle` so changing
/// language at runtime takes effect on the next body re-evaluation.
func T(_ key: LocalizedStringKey) -> Text {
    Text(key, bundle: LocaleProvider.currentBundle)
}

extension View {
    func helpL(_ key: String) -> some View {
        self.help(L10n.t(key))
    }
}

/// Persist the override into AppleLanguages so the *next* process launches in
/// the chosen locale even before AppState reads preferences.
enum LanguageOverrideApplier {
    static func apply(_ override: LanguageOverride) {
        switch override {
        case .system:
            UserDefaults.standard.removeObject(forKey: "AppleLanguages")
        case .en:
            UserDefaults.standard.set(["en"], forKey: "AppleLanguages")
        case .ja:
            UserDefaults.standard.set(["ja"], forKey: "AppleLanguages")
        }
    }
}

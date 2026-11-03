import SwiftUI
import AppKit

@main
struct StatusForecastApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    init() {
        // Apply language override BEFORE any UI is created so the first
        // render uses the chosen language.
        let prefs = PreferencesStore.shared.load()
        LocaleProvider.apply(prefs.languageOverride)
        LanguageOverrideApplier.apply(prefs.languageOverride)
    }

    var body: some Scene {
        // No SwiftUI `Settings { }` scene — we manage the settings window
        // manually via SettingsWindowController for reliable front-bringing
        // under LSUIElement.
        Settings { EmptyView() }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let state = AppState()
    private var menuBar: MenuBarController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        menuBar = MenuBarController(appState: state)
        state.bootstrap()
    }
}

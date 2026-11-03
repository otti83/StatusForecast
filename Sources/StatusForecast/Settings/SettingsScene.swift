import SwiftUI

struct SettingsRoot: View {
    @EnvironmentObject var state: AppState
    @State private var tab: Tab = .general

    enum Tab: String, Hashable { case general, locations, refresh, advanced }

    var body: some View {
        TabView(selection: $tab) {
            GeneralTab()
                .tabItem { Label { T("settings.tab.general") } icon: { Image(systemName: "gearshape") } }
                .tag(Tab.general)
            LocationsTab()
                .tabItem { Label { T("settings.tab.locations") } icon: { Image(systemName: "mappin.and.ellipse") } }
                .tag(Tab.locations)
            RefreshTab()
                .tabItem { Label { T("settings.tab.refresh") } icon: { Image(systemName: "arrow.clockwise") } }
                .tag(Tab.refresh)
            AdvancedTab()
                .tabItem { Label { T("settings.tab.advanced") } icon: { Image(systemName: "wrench.and.screwdriver") } }
                .tag(Tab.advanced)
        }
        .frame(width: 580, height: 480)
        .environment(\.locale, state.effectiveLocale)
        .id(state.preferences.languageOverride)
    }
}

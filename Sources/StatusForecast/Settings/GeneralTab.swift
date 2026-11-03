import SwiftUI
import ServiceManagement

struct GeneralTab: View {
    @EnvironmentObject var state: AppState
    @State private var loginItemError: String?

    var body: some View {
        Form {
            Section {
                Picker(selection: Binding(
                    get: { state.preferences.displayMode },
                    set: { state.preferences.displayMode = $0 }
                )) {
                    ForEach(MenuBarDisplayMode.allCases, id: \.self) { mode in
                        T(LocalizedStringKey(mode.labelKey)).tag(mode)
                    }
                } label: { T("settings.general.menubar_mode") }

                Picker(selection: Binding(
                    get: { state.preferences.iconStyle },
                    set: { state.preferences.iconStyle = $0 }
                )) {
                    ForEach(IconStyle.allCases, id: \.self) { style in
                        T(LocalizedStringKey(style.labelKey)).tag(style)
                    }
                } label: { T("settings.general.icon") }

                Toggle(isOn: Binding(
                    get: { state.preferences.showDegreeDecimal },
                    set: { state.preferences.showDegreeDecimal = $0 }
                )) { T("settings.general.decimal") }

                Picker(selection: Binding(
                    get: { state.preferences.unitSystem },
                    set: { state.preferences.unitSystem = $0 }
                )) {
                    ForEach(UnitSystem.allCases, id: \.self) { u in
                        T(LocalizedStringKey(u.labelKey)).tag(u)
                    }
                } label: { T("settings.general.unit") }
            } header: { T("settings.general.display") }

            Section {
                Picker(selection: Binding(
                    get: { state.preferences.languageOverride },
                    set: {
                        state.preferences.languageOverride = $0
                        LanguageOverrideApplier.apply($0)
                    }
                )) {
                    ForEach(LanguageOverride.allCases, id: \.self) { lang in
                        T(LocalizedStringKey(lang.labelKey)).tag(lang)
                    }
                } label: { T("settings.general.language") }
                T("settings.general.language_note")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            } header: { T("settings.general.language") }

            Section {
                Toggle(isOn: Binding(
                    get: { state.preferences.launchAtLogin },
                    set: { newValue in
                        state.preferences.launchAtLogin = newValue
                        applyLaunchAtLogin(newValue)
                    }
                )) { T("settings.general.launch_at_login") }

                if let err = loginItemError {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 4) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundStyle(.orange)
                            Text(err)
                                .font(.caption)
                                .foregroundStyle(.orange)
                        }
                        Button {
                            if let url = URL(string: "x-apple.systempreferences:com.apple.LoginItems-Settings.extension") {
                                NSWorkspace.shared.open(url)
                            }
                        } label: {
                            T("settings.general.open_login_items")
                        }
                        .controlSize(.small)
                    }
                }

                Toggle(isOn: Binding(
                    get: { state.preferences.refreshOnLaunch },
                    set: { state.preferences.refreshOnLaunch = $0 }
                )) { T("settings.general.refresh_on_launch") }
            } header: { T("settings.general.startup") }
        }
        .formStyle(.grouped)
        .padding()
    }

    private func applyLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled { try SMAppService.mainApp.register() }
            else        { try SMAppService.mainApp.unregister() }
            loginItemError = nil
        } catch {
            // Surface the error so the user knows something went wrong and
            // can hop to System Settings to grant permission manually.
            loginItemError = "\(error.localizedDescription)"
        }
    }
}

import SwiftUI

struct RefreshTab: View {
    @EnvironmentObject var state: AppState

    var body: some View {
        Form {
            Picker(selection: Binding(
                get: { state.preferences.refreshInterval },
                set: {
                    state.preferences.refreshInterval = $0
                    state.scheduleAutomaticRefresh()
                }
            )) {
                ForEach(RefreshInterval.allCases, id: \.self) { interval in
                    Text(L10n.tf("refresh.minutes", interval.rawValue)).tag(interval)
                }
            } label: { T("settings.refresh.interval") }

            Toggle(isOn: Binding(
                get: { state.preferences.wifiOnly },
                set: { state.preferences.wifiOnly = $0 }
            )) { T("settings.refresh.wifi_only") }

            HStack {
                T("settings.refresh.last")
                Spacer()
                if let last = state.snapshot?.fetchedAt {
                    Text(last, format: Date.FormatStyle()
                            .year().month().day()
                            .hour(.defaultDigits(amPM: .omitted))
                            .minute(.twoDigits)
                            .locale(state.effectiveLocale))
                        .foregroundStyle(.secondary)
                } else {
                    Text("—").foregroundStyle(.secondary)
                }
            }
            HStack {
                Button { state.refresh(force: true) } label: { T("settings.refresh.now") }
                if state.loadState.isLoading {
                    ProgressView().controlSize(.small)
                }
                Spacer()
            }
        }
        .formStyle(.grouped)
        .padding()
    }

}

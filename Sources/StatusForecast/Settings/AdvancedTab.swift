import SwiftUI

struct AdvancedTab: View {
    @EnvironmentObject var state: AppState
    @State private var cacheNotice: String?

    var body: some View {
        Form {
            Section {
                Button {
                    let url = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)
                        .first?.appendingPathComponent("com.statusforecast.app")
                    if let url {
                        try? FileManager.default.removeItem(at: url)
                        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
                    }
                    cacheNotice = L10n.t("settings.advanced.cache_cleared")
                } label: { T("settings.advanced.clear_cache") }
                if let n = cacheNotice {
                    Text(n).font(.caption).foregroundStyle(.secondary)
                }
            } header: { T("settings.advanced.maintenance") }

            Section {
                VStack(alignment: .leading, spacing: 4) {
                    Text("• Weather data by Open-Meteo.com (CC-BY 4.0)")
                    Link("Open-Meteo", destination: URL(string: "https://open-meteo.com/")!)
                }
                .font(.caption)
            } header: { T("settings.advanced.credits") }
        }
        .formStyle(.grouped)
        .padding()
    }
}

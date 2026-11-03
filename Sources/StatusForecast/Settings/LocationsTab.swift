import SwiftUI

struct LocationsTab: View {
    @EnvironmentObject var state: AppState
    @State private var addSheet = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                T("settings.locations.registered").font(.headline)
                Spacer()
                Button {
                    addSheet = true
                } label: {
                    Label { T("settings.locations.add") } icon: { Image(systemName: "plus") }
                }
            }
            List {
                ForEach(state.preferences.locations) { loc in
                    HStack {
                        Image(systemName: loc.id == state.preferences.selectedLocationID ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(.blue)
                            .onTapGesture { state.selectLocation(loc.id) }
                        VStack(alignment: .leading, spacing: 2) {
                            Text(loc.displayName)
                            Text("\(String(format: "%.3f", loc.latitude)), \(String(format: "%.3f", loc.longitude)) · \(loc.timeZoneIdentifier)")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        if state.preferences.locations.count > 1 {
                            Button(role: .destructive) {
                                state.removeLocation(loc.id)
                            } label: {
                                Image(systemName: "trash")
                            }
                            .buttonStyle(.borderless)
                        }
                    }
                    .padding(.vertical, 4)
                }
                .onMove { from, to in
                    state.preferences.locations.move(fromOffsets: from, toOffset: to)
                }
            }
            .listStyle(.bordered)
        }
        .padding()
        .sheet(isPresented: $addSheet) {
            LocationSearchSheet(isPresented: $addSheet)
                .environmentObject(state)
        }
    }
}

struct LocationSearchSheet: View {
    @EnvironmentObject var state: AppState
    @Binding var isPresented: Bool
    @State private var query: String = ""
    @State private var hits: [OpenMeteoGeocodingClient.Hit] = []
    @State private var searching: Bool = false
    @State private var debounceTask: Task<Void, Never>?

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField(L10n.t("settings.locations.search_placeholder"), text: $query)
                    .textFieldStyle(.plain)
                    .onChange(of: query) { _, new in scheduleSearch(new) }
                if searching { ProgressView().controlSize(.small) }
                Button { isPresented = false } label: { T("settings.locations.cancel") }
            }
            .padding()
            Divider()
            if hits.isEmpty && !query.isEmpty && !searching {
                VStack {
                    Spacer()
                    T("settings.locations.no_results").foregroundStyle(.secondary)
                    Spacer()
                }
                .frame(maxWidth: .infinity)
            } else {
                List(hits) { hit in
                    Button {
                        let loc = Location(
                            displayName: hit.displayName,
                            latitude: hit.latitude,
                            longitude: hit.longitude,
                            timeZoneIdentifier: hit.timezone,
                            countryCode: hit.countryCode
                        )
                        state.addLocation(loc)
                        isPresented = false
                    } label: {
                        HStack {
                            Image(systemName: "mappin.circle")
                                .foregroundStyle(.secondary)
                                .frame(width: 18)
                            VStack(alignment: .leading) {
                                Text(hit.displayName)
                                Text("\(hit.timezone) · \(hit.countryCode ?? "—")")
                                    .font(.caption2).foregroundStyle(.secondary)
                            }
                            Spacer()
                        }
                    }
                    .buttonStyle(.plain)
                    .padding(.vertical, 2)
                }
                .listStyle(.bordered)
            }
        }
        .frame(width: 520, height: 460)
    }

    private func scheduleSearch(_ raw: String) {
        debounceTask?.cancel()
        let q = raw.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else {
            hits = []
            searching = false
            return
        }
        searching = true
        debounceTask = Task {
            try? await Task.sleep(nanoseconds: 300_000_000)
            if Task.isCancelled { return }
            await runSearch(q)
        }
    }

    private func runSearch(_ q: String) async {
        let lang: String = {
            switch state.preferences.languageOverride {
            case .ja: return "ja"
            case .en: return "en"
            case .system:
                return (Locale.current.language.languageCode?.identifier == "ja") ? "ja" : "en"
            }
        }()
        do {
            let result = try await OpenMeteoGeocodingClient().search(q, language: lang)
            await MainActor.run {
                self.hits = result
                self.searching = false
            }
        } catch {
            await MainActor.run {
                self.hits = []
                self.searching = false
            }
        }
    }
}

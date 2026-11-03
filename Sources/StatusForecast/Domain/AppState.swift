import Foundation
import SwiftUI
import Combine
import Network

enum LoadState: Equatable {
    case idle
    case loading
    case ready
    case stale(message: String)
    case error(message: String)

    var isLoading: Bool { if case .loading = self { return true } else { return false } }
}

@MainActor
final class AppState: ObservableObject {
    @Published var preferences: Preferences {
        didSet {
            PreferencesStore.shared.save(preferences)
            if oldValue.languageOverride != preferences.languageOverride {
                LocaleProvider.apply(preferences.languageOverride)
                LanguageOverrideApplier.apply(preferences.languageOverride)
                objectWillChange.send()
            }
        }
    }

    var effectiveLocale: Locale { LocaleProvider.currentLocale }
    @Published var snapshot: WeatherSnapshot?
    @Published var loadState: LoadState = .idle

    let refreshCoordinator: RefreshCoordinator
    private var refreshTask: Task<Void, Never>?
    private var timerCancellable: AnyCancellable?
    private var settingsController: SettingsWindowController?
    private let netMonitor = NWPathMonitor()
    private var onWiFi: Bool = true

    func openSettings() {
        if settingsController == nil {
            settingsController = SettingsWindowController(state: self)
        }
        settingsController?.show()
    }

    init() {
        let loaded = PreferencesStore.shared.load()
        LocaleProvider.apply(loaded.languageOverride)
        self.preferences = loaded
        self.refreshCoordinator = RefreshCoordinator(openMeteo: OpenMeteoClient())
    }

    func bootstrap() {
        startNetMonitor()
        Task.detached { await DiskCache.shared.purgeOlderThan(7 * 86400) }
        scheduleAutomaticRefresh()
        if preferences.refreshOnLaunch {
            refresh(force: true)
        }
    }

    private func startNetMonitor() {
        netMonitor.pathUpdateHandler = { [weak self] path in
            let wifi = path.usesInterfaceType(.wifi)
            Task { @MainActor in self?.onWiFi = wifi }
        }
        netMonitor.start(queue: DispatchQueue.global(qos: .utility))
    }

    func refresh(force: Bool = false) {
        guard let location = preferences.selectedLocation else {
            loadState = .error(message: L10n.t("error.no_location"))
            return
        }
        if preferences.wifiOnly && !onWiFi && !force {
            loadState = .stale(message: L10n.t("issue.wifi_only_skip"))
            return
        }
        refreshTask?.cancel()
        refreshTask = Task { @MainActor in
            if snapshot == nil { loadState = .loading }
            do {
                let result = try await refreshCoordinator.fetch(for: location)
                snapshot = result
                if result.issues.isEmpty {
                    loadState = .ready
                } else {
                    loadState = .stale(message: result.issues.map(\.message).joined(separator: " / "))
                }
            } catch is CancellationError {
                // ignore
            } catch {
                if snapshot != nil {
                    loadState = .stale(message: "\(error)")
                } else {
                    loadState = .error(message: "\(error)")
                }
            }
        }
    }

    func scheduleAutomaticRefresh() {
        timerCancellable?.cancel()
        let interval = preferences.refreshInterval.seconds
        timerCancellable = Timer.publish(every: interval, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in self?.refresh() }
    }

    func selectLocation(_ id: UUID) {
        preferences.selectedLocationID = id
        refresh(force: true)
    }

    func addLocation(_ location: Location) {
        var locs = preferences.locations
        let duplicate = locs.contains { existing in
            abs(existing.latitude - location.latitude) < 0.0001 &&
            abs(existing.longitude - location.longitude) < 0.0001
        }
        if !duplicate { locs.append(location) }
        preferences.locations = locs
        preferences.selectedLocationID = locs.last?.id
        refresh(force: true)
    }

    func removeLocation(_ id: UUID) {
        preferences.locations.removeAll { $0.id == id }
        if preferences.selectedLocationID == id {
            preferences.selectedLocationID = preferences.locations.first?.id
        }
        refresh(force: true)
    }
}

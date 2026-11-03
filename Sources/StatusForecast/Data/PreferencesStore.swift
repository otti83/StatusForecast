import Foundation

/// UserDefaults-backed Codable store for Preferences.
final class PreferencesStore {
    static let shared = PreferencesStore()

    private let key = "preferences.v3"
    private let defaults = UserDefaults.standard

    private init() {}

    func load() -> Preferences {
        if let data = defaults.data(forKey: key),
           let p = try? JSONDecoder().decode(Preferences.self, from: data),
           !p.locations.isEmpty {
            return p
        }
        return Preferences.default
    }

    func save(_ prefs: Preferences) {
        if let data = try? JSONEncoder().encode(prefs) {
            defaults.set(data, forKey: key)
        }
    }
}

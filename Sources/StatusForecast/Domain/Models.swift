import Foundation

// MARK: - Location

struct Location: Codable, Identifiable, Hashable, Sendable {
    var id: UUID = UUID()
    var displayName: String          // e.g. "Tokyo, Tokyo, Japan"
    var latitude: Double
    var longitude: Double
    var timeZoneIdentifier: String   // e.g. "Asia/Tokyo"
    var countryCode: String?         // ISO 3166-1 alpha-2

    var timeZone: TimeZone {
        TimeZone(identifier: timeZoneIdentifier) ?? TimeZone(identifier: "UTC")!
    }

    var calendar: Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = timeZone
        return cal
    }
}

// MARK: - Weather code reference

/// Open-Meteo (WMO) weather code reference.
enum WeatherCodeRef: Codable, Hashable, Sendable {
    case wmo(Int)
    case unknown
}

// MARK: - Snapshots

struct WeatherSnapshot: Sendable {
    let location: Location
    let fetchedAt: Date
    let current: CurrentWeather?
    let today: DailyForecast?
    let upcoming: [DailyForecast]
    let weekly: [DailyForecast]
    let hourly: [HourlyForecast]
    let airQuality: AirQualitySnapshot?
    let grid: [GridPoint]
    let issues: [SourceIssue]
}

/// Single sample point in a small lat/lon grid around the selected location.
/// Drives the "Nearby" map view.
struct GridPoint: Sendable, Hashable, Identifiable {
    var id: String { "\(latitude),\(longitude)" }
    let latitude: Double
    let longitude: Double
    let temperatureC: Double?
    let windSpeedMps: Double?
    let windDirectionDeg: Double?
    let weatherCode: Int?
}

struct HourlyForecast: Sendable, Hashable, Identifiable {
    var id: Date { time }
    let time: Date
    let temperatureC: Double?
    let humidity: Double?
    let windSpeedMps: Double?
    let windDirectionDeg: Double?
    let precipitationMm: Double?
    let precipitationProbability: Int?
    let weatherCode: Int?
    var uvIndex: Double? = nil
    var visibilityMeters: Double? = nil
    var cloudCoverPct: Double? = nil
    var cloudCoverLowPct: Double? = nil
    var cloudCoverMidPct: Double? = nil
    var cloudCoverHighPct: Double? = nil
    var pressureMslHPa: Double? = nil
    var windGustsMps: Double? = nil
    var shortwaveRadiation: Double? = nil   // W/m²
}

struct SourceIssue: Sendable, Hashable {
    enum Source: String, Sendable { case openMeteo }
    let source: Source
    let message: String
}

struct CurrentWeather: Sendable, Hashable {
    let observedAt: Date
    let temperatureC: Double?
    let humidity: Double?
    let windDirectionDeg: Double?
    let windSpeedMps: Double?
    let precip1hMm: Double?
    let pressureHPa: Double?
}

struct DailyForecast: Sendable, Hashable, Identifiable {
    var id: Date { date }
    let date: Date
    let code: WeatherCodeRef
    let tempMinC: Double?
    let tempMaxC: Double?
    let pops: [PrecipChance]
    var sunrise: Date? = nil
    var sunset: Date? = nil
    var uvIndexMax: Double? = nil
    var sunshineSeconds: Double? = nil
}

// MARK: - Air quality

struct AirQualitySnapshot: Sendable, Hashable {
    let hourly: [AirQualityHourly]
}

struct AirQualityHourly: Sendable, Hashable, Identifiable {
    var id: Date { time }
    let time: Date
    let usAqi: Int?
    let pm25: Double?
    let pm10: Double?
}

struct PrecipChance: Sendable, Hashable {
    let start: Date
    let end: Date
    let percent: Int?
}

// MARK: - Menu bar enums

enum MenuBarDisplayMode: String, Codable, CaseIterable, Sendable {
    case weekly, realtime, daily
    var labelKey: String {
        switch self {
        case .weekly:   return "display.weekly"
        case .realtime: return "display.realtime"
        case .daily:    return "display.daily"
        }
    }
}

enum IconStyle: String, Codable, CaseIterable, Sendable {
    case monochrome, color
    var labelKey: String { self == .monochrome ? "icon.mono" : "icon.color" }
}

enum RefreshInterval: Int, Codable, CaseIterable, Sendable {
    case fiveMin = 5
    case tenMin = 10
    case fifteenMin = 15
    case thirtyMin = 30
    case sixtyMin = 60

    var seconds: TimeInterval { TimeInterval(rawValue * 60) }
}

// MARK: - Preferences

enum LanguageOverride: String, Codable, CaseIterable, Sendable {
    case system, en, ja
    var labelKey: String {
        switch self {
        case .system: return "settings.general.language.system"
        case .en:     return "settings.general.language.en"
        case .ja:     return "settings.general.language.ja"
        }
    }
}

enum UnitSystem: String, Codable, CaseIterable, Sendable {
    case metric, imperial   // metric = °C, imperial = °F
    var labelKey: String {
        switch self {
        case .metric:   return "settings.general.unit.metric"
        case .imperial: return "settings.general.unit.imperial"
        }
    }
}

struct Preferences: Codable, Sendable, Equatable {
    var version: Int = 3
    var displayMode: MenuBarDisplayMode = .realtime
    var iconStyle: IconStyle = .monochrome
    var locations: [Location] = []
    var selectedLocationID: UUID?
    var refreshInterval: RefreshInterval = .tenMin
    var refreshOnLaunch: Bool = true
    var wifiOnly: Bool = false
    var launchAtLogin: Bool = false
    var showDegreeDecimal: Bool = false
    var languageOverride: LanguageOverride = .system
    var unitSystem: UnitSystem = .metric

    var selectedLocation: Location? {
        guard let id = selectedLocationID else { return locations.first }
        return locations.first(where: { $0.id == id }) ?? locations.first
    }

    static let `default`: Preferences = {
        var p = Preferences()
        let tokyo = Location(
            displayName: "Tokyo",
            latitude: 35.6895,
            longitude: 139.6917,
            timeZoneIdentifier: "Asia/Tokyo",
            countryCode: "JP"
        )
        p.locations = [tokyo]
        p.selectedLocationID = tokyo.id
        return p
    }()
}

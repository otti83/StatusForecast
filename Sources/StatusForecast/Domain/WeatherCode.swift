import Foundation
import SwiftUI

enum WeatherCategory: String, Sendable {
    case sunny, partlyCloudy, cloudy, rain, heavyRain, sleet, snow, thunder, fog, unknown

    var symbolName: String {
        switch self {
        case .sunny:        return "sun.max.fill"
        case .partlyCloudy: return "cloud.sun.fill"
        case .cloudy:       return "cloud.fill"
        case .rain:         return "cloud.rain.fill"
        case .heavyRain:    return "cloud.heavyrain.fill"
        case .sleet:        return "cloud.sleet.fill"
        case .snow:         return "cloud.snow.fill"
        case .thunder:      return "cloud.bolt.rain.fill"
        case .fog:          return "cloud.fog.fill"
        case .unknown:      return "questionmark.circle"
        }
    }

    var tint: Color {
        switch self {
        case .sunny:        return .orange
        case .partlyCloudy: return .yellow
        case .cloudy:       return .gray
        case .rain:         return .blue
        case .heavyRain:    return .indigo
        case .sleet:        return .teal
        case .snow:         return .cyan
        case .thunder:      return .purple
        case .fog:          return .secondary
        case .unknown:      return .secondary
        }
    }

    var paletteColors: (primary: Color, secondary: Color) {
        switch self {
        case .sunny:        return (.orange, .yellow)
        case .partlyCloudy: return (.gray, .orange)
        case .cloudy:       return (.gray, .gray.opacity(0.7))
        case .rain:         return (.gray, .blue)
        case .heavyRain:    return (.gray, .indigo)
        case .sleet:        return (.gray, .teal)
        case .snow:         return (.gray, .cyan)
        case .thunder:      return (.gray, .yellow)
        case .fog:          return (.gray, .gray.opacity(0.5))
        case .unknown:      return (.secondary, .secondary)
        }
    }

    var localizedLabel: String { L10n.t("weather.\(rawValue)") }
}

// MARK: - Code resolver

enum WeatherCategoryMap {
    static func category(for ref: WeatherCodeRef) -> WeatherCategory {
        switch ref {
        case .wmo(let code): return WMOWeatherCodeMap.category(for: code)
        case .unknown:        return .unknown
        }
    }

    static func symbolName(for ref: WeatherCodeRef) -> String {
        category(for: ref).symbolName
    }
}

/// WMO weather interpretation codes (Open-Meteo). 0..99.
/// https://open-meteo.com/en/docs — "Weather variable documentation"
enum WMOWeatherCodeMap {
    static func category(for code: Int) -> WeatherCategory {
        switch code {
        case 0:                   return .sunny           // clear sky
        case 1, 2:                return .partlyCloudy    // mainly clear, partly cloudy
        case 3:                   return .cloudy          // overcast
        case 45, 48:              return .fog             // fog, depositing rime fog
        case 51, 53, 55:          return .rain            // drizzle
        case 56, 57:              return .sleet           // freezing drizzle
        case 61, 63:              return .rain            // rain
        case 65:                  return .heavyRain
        case 66, 67:              return .sleet           // freezing rain
        case 71, 73, 75, 77:      return .snow
        case 80, 81:              return .rain            // rain showers
        case 82:                  return .heavyRain
        case 85, 86:              return .snow            // snow showers
        case 95:                  return .thunder         // thunderstorm
        case 96, 99:              return .thunder         // thunderstorm w/ hail
        default:                  return .unknown
        }
    }
}

// MARK: - Wind direction

enum WindDirectionMap {
    /// JMA 1..16 -> localized cardinal label.
    /// labels16[0]=NNE (22.5°), so labelKey index = code-1.
    private static let keys = [
        "wind.dir.NNE", "wind.dir.NE", "wind.dir.ENE", "wind.dir.E",
        "wind.dir.ESE", "wind.dir.SE", "wind.dir.SSE", "wind.dir.S",
        "wind.dir.SSW", "wind.dir.SW", "wind.dir.WSW", "wind.dir.W",
        "wind.dir.WNW", "wind.dir.NW", "wind.dir.NNW", "wind.dir.N"
    ]

    static func label(forCode code: Int) -> String {
        guard code >= 1, code <= 16 else { return L10n.t("wind.calm") }
        return L10n.t(keys[code - 1])
    }

    static func degrees(forCode code: Int) -> Double {
        guard code >= 1, code <= 16 else { return 0 }
        return 22.5 * Double(code)
    }

    /// Generic bearing -> 16-point cardinal label for Open-Meteo current data.
    static func label(forDegrees deg: Double) -> String {
        let normalized = ((deg.truncatingRemainder(dividingBy: 360)) + 360)
            .truncatingRemainder(dividingBy: 360)
        let index = Int((normalized / 22.5).rounded()) % 16
        // index 0 = N, 1 = NNE, ..., 15 = NNW (clockwise from north)
        let labelsCW = [
            "wind.dir.N", "wind.dir.NNE", "wind.dir.NE", "wind.dir.ENE",
            "wind.dir.E", "wind.dir.ESE", "wind.dir.SE", "wind.dir.SSE",
            "wind.dir.S", "wind.dir.SSW", "wind.dir.SW", "wind.dir.WSW",
            "wind.dir.W", "wind.dir.WNW", "wind.dir.NW", "wind.dir.NNW"
        ]
        return L10n.t(labelsCW[index])
    }
}

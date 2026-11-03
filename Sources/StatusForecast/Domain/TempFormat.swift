import Foundation

/// User-facing temperature formatting. All internal data stays in Celsius;
/// every display point converts here based on `UnitSystem`.
enum TempFormat {
    /// Converts °C to the user's chosen unit (°C or °F).
    static func value(_ c: Double, in unit: UnitSystem) -> Double {
        unit == .imperial ? c * 9.0 / 5.0 + 32.0 : c
    }

    static func unitSuffix(_ unit: UnitSystem) -> String {
        unit == .imperial ? "°F" : "°C"
    }

    /// Integer degrees with half-up rounding. No unit letter — caller can
    /// add °C / °F via `unitSuffix` when needed.
    static func intLabel(_ c: Double, in unit: UnitSystem) -> String {
        let v = value(c, in: unit)
        return "\(Int(v.rounded(.toNearestOrAwayFromZero)))°"
    }

    /// One-decimal place, with unit letter.
    static func oneDecimalLabel(_ c: Double, in unit: UnitSystem) -> String {
        let v = value(c, in: unit)
        return String(format: "%.1f%@", v, unitSuffix(unit))
    }

    /// Chart Y-axis domain converted from Celsius to the user's unit.
    static func domain(_ c: ClosedRange<Double>, in unit: UnitSystem) -> ClosedRange<Double> {
        let lo = value(c.lowerBound, in: unit)
        let hi = value(c.upperBound, in: unit)
        return lo...hi
    }
}

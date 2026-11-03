import SwiftUI
import Charts

struct NowView: View {
    @EnvironmentObject var state: AppState

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 8) {
                hero
                Divider()
                stationGrid
                Divider()
                let allHourly = todayHourlyEntries + tomorrowHourlyEntries
                let unifiedYDomain = combinedYDomain(allHourly)
                let precipScale = combinedPrecipScale(allHourly)
                dayChartSection(
                    titleKey: "section.today_24h",
                    entries: todayHourlyEntries,
                    day: state.snapshot?.today,
                    yDomain: unifiedYDomain,
                    precipScale: precipScale
                )
                Divider()
                dayChartSection(
                    titleKey: "section.tomorrow_24h",
                    entries: tomorrowHourlyEntries,
                    day: state.snapshot?.upcoming.first,
                    yDomain: unifiedYDomain,
                    precipScale: precipScale
                )
            }
        }
    }

    private var location: Location? { state.snapshot?.location }
    private var calendar: Calendar { location?.calendar ?? Calendar(identifier: .gregorian) }

    // MARK: - Hero

    @ViewBuilder
    private var hero: some View {
        HStack(alignment: .top, spacing: 14) {
            if let code = state.snapshot?.today?.code {
                WeatherSymbol(code: code, size: 52, useColor: true)
                    .frame(width: 60, height: 60)
            } else {
                Color.clear.frame(width: 60, height: 60)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(temperatureText)
                    .font(.system(size: 36, weight: .semibold, design: .rounded))
                if let observed = state.snapshot?.current?.observedAt {
                    Text(L10n.tf("section.observation", observed.formatted(timeStyle)))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                if let code = state.snapshot?.today?.code {
                    Text(WeatherCategoryMap.category(for: code).localizedLabel)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 8)
            apparentBlock
        }
    }

    private var temperatureText: String {
        let unit = state.preferences.unitSystem
        if let t = state.snapshot?.current?.temperatureC {
            return TempFormat.oneDecimalLabel(t, in: unit)
        }
        if let t = state.snapshot?.today?.tempMaxC {
            let v = TempFormat.value(t, in: unit)
            return "\(Int(v.rounded(.toNearestOrAwayFromZero)))\(TempFormat.unitSuffix(unit))"
        }
        return "—\(TempFormat.unitSuffix(unit))"
    }

    @ViewBuilder
    private var apparentBlock: some View {
        if let cur = state.snapshot?.current,
           let t = cur.temperatureC, let h = cur.humidity {
            let apparent = Self.apparent(temp: t, humidity: h, wind: cur.windSpeedMps ?? 0)
            let di = Self.discomfort(temp: t, humidity: h)
            VStack(alignment: .trailing, spacing: 2) {
                T("tile.apparent").font(.caption2).foregroundStyle(.secondary)
                Text(TempFormat.oneDecimalLabel(apparent, in: state.preferences.unitSystem))
                    .font(.callout.weight(.semibold))
                Text(L10n.tf("tile.discomfort", Int(di.rounded()), Self.discomfortLabel(di)))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - station grid (AMeDAS for Japan; Open-Meteo current for global)

    @ViewBuilder
    private var stationGrid: some View {
        if let cur = state.snapshot?.current {
            let tiles = buildTiles(cur: cur)
            HStack(alignment: .center, spacing: 8) {
                ForEach(tiles, id: \.title) { tile in
                    StatTile(icon: tile.icon, title: tile.title, value: tile.value, tint: tile.tint)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .fixedSize(horizontal: false, vertical: true)
        } else {
            HStack {
                ProgressView().controlSize(.small)
                T("loading.amedas").font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private func buildTiles(cur: CurrentWeather) -> [StatTileSpec] {
        let unit = state.preferences.unitSystem
        var tiles: [StatTileSpec] = []
        if let lo = state.snapshot?.today?.tempMinC,
           let hi = state.snapshot?.today?.tempMaxC {
            tiles.append(.init(
                icon: "thermometer.medium",
                title: L10n.t("tile.temp_range"),
                value: "\(TempFormat.intLabel(lo, in: unit))/\(TempFormat.intLabel(hi, in: unit))",
                tint: .orange
            ))
        }
        if let h = cur.humidity {
            tiles.append(.init(icon: "humidity.fill",
                               title: L10n.t("tile.humidity"),
                               value: "\(Int(h))%", tint: .blue))
        }
        tiles.append(.init(icon: "wind",
                           title: L10n.t("tile.wind"),
                           value: Self.windText(cur), tint: .teal))
        if let p = cur.pressureHPa {
            tiles.append(.init(icon: "gauge.with.dots.needle.bottom.50percent",
                               title: L10n.t("tile.pressure"),
                               value: String(format: "%.0fhPa", p), tint: .purple))
        }
        if let r1 = cur.precip1hMm {
            tiles.append(.init(icon: "drop.fill",
                               title: L10n.t("tile.rain_1h"),
                               value: String(format: "%.1fmm", r1), tint: .indigo))
        }
        return tiles
    }

    // MARK: - Day-bounded hourly slices

    private var todayHourlyEntries: [HourlyForecast] {
        hourly(forDayOffset: 0)
    }

    private var tomorrowHourlyEntries: [HourlyForecast] {
        hourly(forDayOffset: 1)
    }

    private func hourly(forDayOffset offset: Int) -> [HourlyForecast] {
        guard let snap = state.snapshot else { return [] }
        let cal = calendar
        let base = cal.startOfDay(for: Date())
        guard let dayStart = cal.date(byAdding: .day, value: offset, to: base),
              let dayEnd = cal.date(byAdding: .day, value: 1, to: dayStart) else { return [] }
        return snap.hourly.filter { $0.time >= dayStart && $0.time < dayEnd }
    }

    /// Combined Y-axis domain across multiple days so today and tomorrow
    /// share the same scale. Computed in Celsius then converted to the
    /// user's unit so step rounding (5° in C, 10° in F) lines up cleanly.
    private func combinedYDomain(_ all: [HourlyForecast]) -> ClosedRange<Double> {
        let unit = state.preferences.unitSystem
        let temps = all.compactMap { $0.temperatureC }
        guard let lo = temps.min(), let hi = temps.max() else {
            return TempFormat.domain(0...35, in: unit)
        }
        let step: Double = unit == .imperial ? 10 : 5
        let pad: Double = unit == .imperial ? 5 : 3
        let loC = floor((lo - pad) / step) * step
        let hiC = ceil((hi + pad) / step) * step
        return TempFormat.domain(loC...hiC, in: unit)
    }

    /// Maximum mm/h across all displayed days, with a 2mm floor so a light
    /// drizzle still renders as a visible bar. Used to scale the rainfall
    /// bars so the band always tops out at the heaviest hour.
    private func combinedPrecipScale(_ all: [HourlyForecast]) -> Double {
        let values = all.compactMap(\.precipitationMm).filter { $0 > 0 }
        let raw = values.max() ?? 0
        return max(2.0, ceil(raw))
    }

    @ViewBuilder
    private func dayChartSection(titleKey: String, entries: [HourlyForecast], day: DailyForecast?, yDomain: ClosedRange<Double>, precipScale: Double) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                T(LocalizedStringKey(titleKey))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
            }
            // Axis unit headers — sit one full text row above the chart so
            // they don't overlap the plot border.
            HStack {
                Text(L10n.tf("chart.label.temp",
                             TempFormat.unitSuffix(state.preferences.unitSystem)))
                    .foregroundStyle(.secondary)
                Spacer()
                T("chart.label.precip")
                    .foregroundStyle(.cyan.opacity(0.85))
            }
            .font(.system(size: 9, weight: .medium))
            if !entries.isEmpty {
                HourlyTempChart(
                    entries: entries,
                    sunrise: day?.sunrise,
                    sunset: day?.sunset,
                    calendar: calendar,
                    locale: state.effectiveLocale,
                    yDomain: yDomain,
                    unit: state.preferences.unitSystem,
                    precipScale: precipScale
                )
                .frame(height: 170)
            } else {
                Text("—")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .frame(height: 170)
            }
        }
    }

    // MARK: - helpers

    static func windText(_ cur: CurrentWeather) -> String {
        let speed = cur.windSpeedMps.map { String(format: "%.1f", $0) } ?? "—"
        if let deg = cur.windDirectionDeg {
            return "\(WindDirectionMap.label(forDegrees: deg)) \(speed)m/s"
        }
        return "\(speed)m/s"
    }

    static func apparent(temp t: Double, humidity rh: Double, wind v: Double) -> Double {
        let e = (rh / 100.0) * 6.105 * exp((17.27 * t) / (237.7 + t))
        return t + 0.348 * e - 0.7 * v - 4.25
    }

    static func discomfort(temp t: Double, humidity rh: Double) -> Double {
        0.81 * t + 0.01 * rh * (0.99 * t - 14.3) + 46.3
    }

    static func discomfortLabel(_ di: Double) -> String {
        switch di {
        case ..<55:    return L10n.t("discomfort.chilly")
        case ..<60:    return L10n.t("discomfort.neutral")
        case ..<65:    return L10n.t("discomfort.comfortable")
        case ..<70:    return L10n.t("discomfort.warm")
        case ..<75:    return L10n.t("discomfort.hot")
        case ..<80:    return L10n.t("discomfort.sweaty")
        default:       return L10n.t("discomfort.extreme")
        }
    }

    private var timeStyle: Date.FormatStyle {
        var s = Date.FormatStyle()
            .month(.abbreviated)
            .day()
            .hour(.defaultDigits(amPM: .omitted))
            .minute(.twoDigits)
            .locale(state.effectiveLocale)
        s.timeZone = location?.timeZone ?? .current
        return s
    }
}

private struct StatTileSpec {
    let icon: String
    let title: String
    let value: String
    let tint: Color
}

private struct StatTile: View {
    let icon: String
    let title: String
    let value: String
    let tint: Color

    var body: some View {
        HStack(alignment: .center, spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 14))
                .foregroundStyle(tint)
                .frame(width: 16)
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Text(value)
                    .font(.system(size: 12, weight: .medium))
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct HourlyTempChart: View {
    let entries: [HourlyForecast]
    let sunrise: Date?
    let sunset: Date?
    let calendar: Calendar
    let locale: Locale
    /// Externally supplied Y-axis range, already in the user's display unit.
    let yDomain: ClosedRange<Double>
    let unit: UnitSystem
    /// mm value mapped to the chart top (full bar). Heavier hours clip.
    let precipScale: Double

    /// Three-row tick label: hour (only at 3h boundaries) / temp / POP.
    /// Non-3h ticks reserve the hour-row space so labels align across all
    /// 24 columns. POP shown as a bare integer (no '%') in a smaller font
    /// since two-digit values were colliding at high probabilities.
    @ViewBuilder
    private func multiLineLabel(for date: Date) -> some View {
        let h = calendar.component(.hour, from: date)
        let entry = entries.first {
            calendar.component(.hour, from: $0.time) == h
        }
        VStack(spacing: 0) {
            Text(h % 3 == 0 ? "\(h)h" : " ")
                .font(.system(size: 9))
                .foregroundStyle(.secondary)
            Group {
                if let t = entry?.temperatureC {
                    Text(TempFormat.intLabel(t, in: unit))
                        .foregroundStyle(.orange)
                } else {
                    Text(" ")
                }
            }
            .font(.system(size: 8, weight: .medium))
            Group {
                if let p = entry?.precipitationProbability {
                    Text("\(p)%")
                        .foregroundStyle(.cyan)
                } else {
                    Text(" ")
                }
            }
            .font(.system(size: 7, weight: .medium))
        }
    }

    var body: some View {
        let dom = yDomain
        let span = dom.upperBound - dom.lowerBound

        Chart {
            // Precipitation bars (mm/h) — bar height maps mm to chart height.
            ForEach(entries) { h in
                if let mm = h.precipitationMm, mm > 0 {
                    let clamped = min(mm, precipScale)
                    BarMark(
                        x: .value("time", h.time),
                        yStart: .value("base", dom.lowerBound),
                        yEnd: .value("mm", dom.lowerBound + span * (clamped / precipScale))
                    )
                    .foregroundStyle(Color.cyan.opacity(0.30))
                }
            }

            // Sunrise / sunset vertical rules — icon-only at top.
            if let sunrise {
                RuleMark(x: .value("sunrise", sunrise))
                    .foregroundStyle(Color.orange.opacity(0.6))
                    .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [3, 3]))
                    .annotation(position: .top, alignment: .center, spacing: 1) {
                        Image(systemName: "sunrise.fill")
                            .symbolRenderingMode(.palette)
                            .foregroundStyle(.orange, .yellow)
                            .font(.system(size: 11))
                    }
            }
            if let sunset {
                RuleMark(x: .value("sunset", sunset))
                    .foregroundStyle(Color.purple.opacity(0.6))
                    .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [3, 3]))
                    .annotation(position: .top, alignment: .center, spacing: 1) {
                        Image(systemName: "sunset.fill")
                            .symbolRenderingMode(.palette)
                            .foregroundStyle(.orange, .purple)
                            .font(.system(size: 11))
                    }
            }

            // Temperature line + points (thicker stroke).
            ForEach(entries) { h in
                if let t = h.temperatureC {
                    let v = TempFormat.value(t, in: unit)
                    LineMark(x: .value("time", h.time), y: .value("temp", v))
                        .interpolationMethod(.catmullRom)
                        .foregroundStyle(.orange)
                        .lineStyle(StrokeStyle(lineWidth: 2.2, lineCap: .round, lineJoin: .round))
                }
            }
            ForEach(entries) { h in
                if let t = h.temperatureC {
                    let v = TempFormat.value(t, in: unit)
                    PointMark(x: .value("time", h.time), y: .value("temp", v))
                        .symbolSize(22)
                        .foregroundStyle(.orange)
                }
            }

        }
        .chartXAxis {
            // 3-hour dashed guide lines.
            AxisMarks(values: .stride(by: .hour, count: 3)) { value in
                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [3, 3]))
                    .foregroundStyle(Color.secondary.opacity(0.45))
            }
            // 1-hour stack labels: hour (at 3h boundaries) / temp / POP%.
            AxisMarks(values: .stride(by: .hour, count: 1)) { value in
                AxisValueLabel {
                    if let date = value.as(Date.self) {
                        multiLineLabel(for: date)
                    }
                }
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading) { value in
                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.7))
                    .foregroundStyle(Color.secondary.opacity(0.45))
                AxisValueLabel {
                    if let v = value.as(Double.self) {
                        Text("\(Int(v))").font(.caption2)
                    }
                }
            }
            AxisMarks(position: .trailing, values: [
                dom.lowerBound,
                dom.upperBound
            ]) { value in
                AxisValueLabel {
                    if let v = value.as(Double.self) {
                        let mm = ((v - dom.lowerBound) / span) * precipScale
                        Text(String(format: "%.0f", mm))
                            .font(.caption2)
                            .foregroundStyle(.cyan.opacity(0.85))
                    }
                }
            }
        }
        .chartYScale(domain: dom)
        .chartPlotStyle { plot in
            plot.border(Color.secondary.opacity(0.9), width: 1)
        }
    }

}


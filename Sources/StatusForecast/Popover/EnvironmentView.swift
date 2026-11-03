import SwiftUI
import Charts

struct EnvironmentView: View {
    @EnvironmentObject var state: AppState

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 8) {
                uvSection
                Divider()
                aqiSection
                Divider()
                humiditySection
                Divider()
                pressureSection
                Divider()
                windSection
                Divider()
                visibilitySection
                Divider()
                cloudLayersSection
                Divider()
                radiationSection
                Divider()
                miscRow
            }
        }
    }

    // MARK: - Generic compact chart helpers

    private func sectionHeader(_ titleKey: String, trailing: String? = nil) -> some View {
        HStack(alignment: .firstTextBaseline) {
            T(LocalizedStringKey(titleKey))
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Spacer()
            if let t = trailing {
                Text(t).font(.caption2).foregroundStyle(.secondary)
            }
        }
    }

    private var commonXAxis: some AxisContent {
        AxisMarks(values: .stride(by: .hour, count: 6)) { value in
            AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5))
                .foregroundStyle(.secondary.opacity(0.3))
            AxisValueLabel {
                if let d = value.as(Date.self) {
                    Text("\(calendar.component(.hour, from: d))").font(.caption2)
                }
            }
        }
    }

    @ChartContentBuilder
    private func lineSeries(_ entries: [HourlyForecast], _ getter: @escaping (HourlyForecast) -> Double?, _ name: String, color: Color) -> some ChartContent {
        ForEach(entries) { h in
            if let v = getter(h) {
                LineMark(x: .value("t", h.time), y: .value(name, v))
                    .interpolationMethod(.catmullRom)
                    .foregroundStyle(color)
                    .lineStyle(StrokeStyle(lineWidth: 1.8, lineCap: .round))
            }
        }
    }

    // MARK: - Humidity

    @ViewBuilder
    private var humiditySection: some View {
        let entries = todayHourly
        let now = entries.first(where: { isCurrentHour($0.time) })?.humidity
        VStack(alignment: .leading, spacing: 6) {
            sectionHeader("env.humidity",
                          trailing: now.map { String(format: "%.0f%%", $0) })
            Chart {
                lineSeries(entries, { $0.humidity }, "rh", color: .blue)
                ForEach(entries) { h in
                    if let v = h.humidity {
                        AreaMark(x: .value("t", h.time), y: .value("rh", v))
                            .foregroundStyle(.blue.opacity(0.12))
                    }
                }
            }
            .chartXAxis { commonXAxis }
            .chartYAxis {
                AxisMarks(position: .leading, values: [0, 50, 100]) { value in
                    AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5))
                        .foregroundStyle(.secondary.opacity(0.3))
                    AxisValueLabel {
                        if let v = value.as(Double.self) { Text("\(Int(v))").font(.caption2) }
                    }
                }
            }
            .chartYScale(domain: 0...100)
            .chartPlotStyle { $0.border(Color.secondary.opacity(0.7), width: 1) }
            .frame(height: 70)
        }
    }

    // MARK: - Pressure

    @ViewBuilder
    private var pressureSection: some View {
        let entries = todayHourly
        let values = entries.compactMap(\.pressureMslHPa)
        let now = entries.first(where: { isCurrentHour($0.time) })?.pressureMslHPa
        let domain: ClosedRange<Double> = {
            guard let lo = values.min(), let hi = values.max() else { return 990...1030 }
            let pad = max(2, (hi - lo) * 0.2)
            return floor(lo - pad)...ceil(hi + pad)
        }()
        VStack(alignment: .leading, spacing: 6) {
            sectionHeader("env.pressure",
                          trailing: now.map { String(format: "%.0f hPa", $0) })
            Chart {
                lineSeries(entries, { $0.pressureMslHPa }, "p", color: .purple)
            }
            .chartXAxis { commonXAxis }
            .chartYAxis {
                AxisMarks(position: .leading) { value in
                    AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5))
                        .foregroundStyle(.secondary.opacity(0.3))
                    AxisValueLabel {
                        if let v = value.as(Double.self) { Text("\(Int(v))").font(.caption2) }
                    }
                }
            }
            .chartYScale(domain: domain)
            .chartPlotStyle { $0.border(Color.secondary.opacity(0.7), width: 1) }
            .frame(height: 70)
        }
    }

    // MARK: - Wind speed + gusts

    @ViewBuilder
    private var windSection: some View {
        let entries = todayHourly
        let curWind = entries.first(where: { isCurrentHour($0.time) })?.windSpeedMps
        let curGust = entries.first(where: { isCurrentHour($0.time) })?.windGustsMps
        let trailing: String? = {
            switch (curWind, curGust) {
            case let (w?, g?): return String(format: "%.1f / %.1f m/s", w, g)
            case let (w?, _):  return String(format: "%.1f m/s", w)
            default:           return nil
            }
        }()
        let allVals = entries.compactMap { $0.windGustsMps ?? $0.windSpeedMps }
        let hi = allVals.max() ?? 10
        VStack(alignment: .leading, spacing: 6) {
            sectionHeader("env.wind", trailing: trailing)
            Chart {
                ForEach(entries) { h in
                    if let g = h.windGustsMps {
                        LineMark(x: .value("t", h.time), y: .value("g", g),
                                 series: .value("k", L10n.t("env.wind.gust")))
                            .interpolationMethod(.catmullRom)
                            .foregroundStyle(.orange)
                            .lineStyle(StrokeStyle(lineWidth: 1.2, dash: [3, 2]))
                    }
                }
                ForEach(entries) { h in
                    if let w = h.windSpeedMps {
                        LineMark(x: .value("t", h.time), y: .value("w", w),
                                 series: .value("k", L10n.t("env.wind.solid")))
                            .interpolationMethod(.catmullRom)
                            .foregroundStyle(.teal)
                            .lineStyle(StrokeStyle(lineWidth: 1.8))
                    }
                }
            }
            .chartLegend(.hidden)
            .chartXAxis { commonXAxis }
            .chartYAxis {
                AxisMarks(position: .leading) { value in
                    AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5))
                        .foregroundStyle(.secondary.opacity(0.3))
                    AxisValueLabel {
                        if let v = value.as(Double.self) { Text("\(Int(v))").font(.caption2) }
                    }
                }
            }
            .chartYScale(domain: 0...max(5, ceil(hi * 1.15)))
            .chartPlotStyle { $0.border(Color.secondary.opacity(0.7), width: 1) }
            .frame(height: 70)
            HStack(spacing: 10) {
                Label { T("env.wind.solid") } icon: { Rectangle().fill(.teal).frame(width: 12, height: 2) }
                Label { T("env.wind.gust") } icon: { Rectangle().fill(.orange).frame(width: 12, height: 2) }
            }
            .font(.caption2)
            .foregroundStyle(.secondary)
        }
    }

    // MARK: - Visibility

    @ViewBuilder
    private var visibilitySection: some View {
        let entries = todayHourly
        let now = entries.first(where: { isCurrentHour($0.time) })?.visibilityMeters
        let values = entries.compactMap(\.visibilityMeters)
        let maxV = max(20000.0, (values.max() ?? 20000) * 1.05)
        VStack(alignment: .leading, spacing: 6) {
            sectionHeader("env.visibility.chart",
                          trailing: now.map { L10n.tf("env.visibility.km", $0 / 1000.0) })
            Chart {
                ForEach(entries) { h in
                    if let v = h.visibilityMeters {
                        AreaMark(x: .value("t", h.time),
                                 y: .value("v", v / 1000.0))
                            .foregroundStyle(.teal.opacity(0.30))
                            .interpolationMethod(.catmullRom)
                    }
                }
                lineSeries(entries, { ($0.visibilityMeters ?? 0) / 1000.0 }, "v", color: .teal)
            }
            .chartXAxis { commonXAxis }
            .chartYAxis {
                AxisMarks(position: .leading, values: [0, maxV / 2000.0, maxV / 1000.0]) { value in
                    AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5))
                        .foregroundStyle(.secondary.opacity(0.3))
                    AxisValueLabel {
                        if let v = value.as(Double.self) { Text("\(Int(v))km").font(.caption2) }
                    }
                }
            }
            .chartYScale(domain: 0...(maxV / 1000.0))
            .chartPlotStyle { $0.border(Color.secondary.opacity(0.7), width: 1) }
            .frame(height: 70)
        }
    }

    // MARK: - Cloud layers (low / mid / high)

    @ViewBuilder
    private var cloudLayersSection: some View {
        let entries = todayHourly
        VStack(alignment: .leading, spacing: 6) {
            sectionHeader("env.cloud.layers")
            Chart {
                ForEach(entries) { h in
                    if let v = h.cloudCoverHighPct {
                        AreaMark(x: .value("t", h.time), y: .value("h", v),
                                 series: .value("k", "high"))
                            .foregroundStyle(.cyan.opacity(0.35))
                            .interpolationMethod(.catmullRom)
                    }
                }
                ForEach(entries) { h in
                    if let v = h.cloudCoverMidPct {
                        AreaMark(x: .value("t", h.time), y: .value("m", v),
                                 series: .value("k", "mid"))
                            .foregroundStyle(.gray.opacity(0.40))
                            .interpolationMethod(.catmullRom)
                    }
                }
                ForEach(entries) { h in
                    if let v = h.cloudCoverLowPct {
                        AreaMark(x: .value("t", h.time), y: .value("l", v),
                                 series: .value("k", "low"))
                            .foregroundStyle(.indigo.opacity(0.35))
                            .interpolationMethod(.catmullRom)
                    }
                }
            }
            .chartLegend(.hidden)
            .chartXAxis { commonXAxis }
            .chartYAxis {
                AxisMarks(position: .leading, values: [0, 50, 100]) { value in
                    AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5))
                        .foregroundStyle(.secondary.opacity(0.3))
                    AxisValueLabel {
                        if let v = value.as(Double.self) { Text("\(Int(v))").font(.caption2) }
                    }
                }
            }
            .chartYScale(domain: 0...100)
            .chartPlotStyle { $0.border(Color.secondary.opacity(0.7), width: 1) }
            .frame(height: 70)
            HStack(spacing: 10) {
                Label { T("env.cloud.low")  } icon: { Rectangle().fill(.indigo.opacity(0.7)).frame(width: 10, height: 6) }
                Label { T("env.cloud.mid")  } icon: { Rectangle().fill(.gray.opacity(0.7)).frame(width: 10, height: 6) }
                Label { T("env.cloud.high") } icon: { Rectangle().fill(.cyan.opacity(0.7)).frame(width: 10, height: 6) }
            }
            .font(.caption2)
            .foregroundStyle(.secondary)
        }
    }

    // MARK: - Solar radiation

    @ViewBuilder
    private var radiationSection: some View {
        let entries = todayHourly
        let now = entries.first(where: { isCurrentHour($0.time) })?.shortwaveRadiation
        let values = entries.compactMap(\.shortwaveRadiation)
        let hi = max(200.0, (values.max() ?? 200) * 1.15)
        VStack(alignment: .leading, spacing: 6) {
            sectionHeader("env.radiation",
                          trailing: now.map { String(format: "%.0f W/m²", $0) })
            Chart {
                ForEach(entries) { h in
                    if let v = h.shortwaveRadiation {
                        AreaMark(x: .value("t", h.time), y: .value("r", v))
                            .foregroundStyle(LinearGradient(
                                colors: [.yellow.opacity(0.5), .orange.opacity(0.2)],
                                startPoint: .top, endPoint: .bottom))
                            .interpolationMethod(.catmullRom)
                    }
                }
                lineSeries(entries, { $0.shortwaveRadiation }, "r", color: .orange)
            }
            .chartXAxis { commonXAxis }
            .chartYAxis {
                AxisMarks(position: .leading) { value in
                    AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5))
                        .foregroundStyle(.secondary.opacity(0.3))
                    AxisValueLabel {
                        if let v = value.as(Double.self) { Text("\(Int(v))").font(.caption2) }
                    }
                }
            }
            .chartYScale(domain: 0...hi)
            .chartPlotStyle { $0.border(Color.secondary.opacity(0.7), width: 1) }
            .frame(height: 70)
        }
    }

    private var location: Location? { state.snapshot?.location }
    private var calendar: Calendar { location?.calendar ?? .current }

    private var todayHourly: [HourlyForecast] {
        guard let snap = state.snapshot else { return [] }
        let cal = calendar
        let start = cal.startOfDay(for: Date())
        let end = cal.date(byAdding: .day, value: 1, to: start)!
        return snap.hourly.filter { $0.time >= start && $0.time < end }
    }

    private var todayAQI: [AirQualityHourly] {
        guard let aq = state.snapshot?.airQuality else { return [] }
        let cal = calendar
        let start = cal.startOfDay(for: Date())
        let end = cal.date(byAdding: .day, value: 1, to: start)!
        return aq.hourly.filter { $0.time >= start && $0.time < end }
    }

    // MARK: - UV

    @ViewBuilder
    private var uvSection: some View {
        let entries = todayHourly
        let current = entries.first(where: { isCurrentHour($0.time) })?.uvIndex
            ?? state.snapshot?.today?.uvIndexMax
        let peak = entries.compactMap { h -> (Date, Double)? in
            guard let u = h.uvIndex else { return nil }
            return (h.time, u)
        }.max(by: { $0.1 < $1.1 })

        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                T("env.uv")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                if let (t, v) = peak {
                    Text(L10n.tf("env.uv.peak_at", t.formatted(hourStyle), v))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            HStack(alignment: .center, spacing: 14) {
                BigValueBadge(
                    value: current.map { String(format: "%.1f", $0) } ?? "—",
                    label: current.map { uvCategoryLabel($0) } ?? "—",
                    color: current.map { uvColor($0) } ?? .secondary
                )
                Chart {
                    ForEach(entries) { h in
                        if let u = h.uvIndex, u > 0 {
                            BarMark(
                                x: .value("t", h.time),
                                y: .value("uv", u),
                                width: .ratio(0.85)
                            )
                            .foregroundStyle(uvColor(u))
                            .cornerRadius(2)
                        }
                    }
                }
                .chartXAxis {
                    AxisMarks(values: .stride(by: .hour, count: 6)) { value in
                        AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5))
                            .foregroundStyle(.secondary.opacity(0.3))
                        AxisValueLabel {
                            if let d = value.as(Date.self) {
                                Text("\(calendar.component(.hour, from: d))").font(.caption2)
                            }
                        }
                    }
                }
                .chartYAxis {
                    AxisMarks(position: .leading, values: [0, 4, 8, 12]) { value in
                        AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5))
                            .foregroundStyle(.secondary.opacity(0.3))
                        AxisValueLabel {
                            if let v = value.as(Double.self) {
                                Text("\(Int(v))").font(.caption2)
                            }
                        }
                    }
                }
                .chartYScale(domain: 0...12)
                .chartPlotStyle { plot in
                    plot.border(Color.secondary.opacity(0.7), width: 1)
                }
                .frame(height: 70)
            }
        }
    }

    // MARK: - AQI

    @ViewBuilder
    private var aqiSection: some View {
        let entries = todayAQI
        let current = entries.first(where: { isCurrentHour($0.time) })
            ?? entries.last
        let pm25 = current?.pm25
        let aqi = current?.usAqi

        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                T("env.aqi")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                if let pm = pm25 {
                    Text(L10n.tf("env.aqi.pm25", pm))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            HStack(alignment: .center, spacing: 14) {
                BigValueBadge(
                    value: aqi.map { "\($0)" } ?? "—",
                    label: aqi.map { aqiCategoryLabel($0) } ?? "—",
                    color: aqi.map { aqiColor($0) } ?? .secondary
                )
                Chart {
                    ForEach(entries) { h in
                        if let a = h.usAqi {
                            BarMark(
                                x: .value("t", h.time),
                                y: .value("aqi", a),
                                width: .ratio(0.85)
                            )
                            .foregroundStyle(aqiColor(a))
                            .cornerRadius(2)
                        }
                    }
                }
                .chartXAxis {
                    AxisMarks(values: .stride(by: .hour, count: 6)) { value in
                        AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5))
                            .foregroundStyle(.secondary.opacity(0.3))
                        AxisValueLabel {
                            if let d = value.as(Date.self) {
                                Text("\(calendar.component(.hour, from: d))").font(.caption2)
                            }
                        }
                    }
                }
                .chartYAxis {
                    AxisMarks(position: .leading, values: [0, 50, 100, 150]) { value in
                        AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5))
                            .foregroundStyle(.secondary.opacity(0.3))
                        AxisValueLabel {
                            if let v = value.as(Double.self) {
                                Text("\(Int(v))").font(.caption2)
                            }
                        }
                    }
                }
                .chartYScale(domain: 0...max(150, Double((entries.compactMap(\.usAqi).max() ?? 0) + 20)))
                .chartPlotStyle { plot in
                    plot.border(Color.secondary.opacity(0.7), width: 1)
                }
                .frame(height: 70)
            }
            if state.snapshot?.airQuality == nil {
                HStack {
                    ProgressView().controlSize(.small)
                    T("loading.env").font(.caption2).foregroundStyle(.secondary)
                }
            }
        }
    }

    // MARK: - misc tiles row

    @ViewBuilder
    private var miscRow: some View {
        HStack(spacing: 10) {
            cloudTile
            visibilityTile
            sunshineTile
        }
        .frame(maxWidth: .infinity)
    }

    private var cloudTile: some View {
        let curHour = todayHourly.first(where: { isCurrentHour($0.time) })
        let pct = curHour?.cloudCoverPct
        return EnvironmentTile(
            icon: "cloud.fill",
            titleKey: "env.cloud",
            value: pct.map { L10n.tf("env.cloud.now", $0) } ?? "—",
            tint: .gray
        )
    }

    private var visibilityTile: some View {
        let curHour = todayHourly.first(where: { isCurrentHour($0.time) })
        let vis = curHour?.visibilityMeters
        return EnvironmentTile(
            icon: "eye.fill",
            titleKey: "env.visibility",
            value: vis.map { L10n.tf("env.visibility.km", $0 / 1000.0) } ?? "—",
            tint: .teal
        )
    }

    private var sunshineTile: some View {
        let seconds = state.snapshot?.today?.sunshineSeconds
        return EnvironmentTile(
            icon: "sun.max.fill",
            titleKey: "env.sunshine",
            value: seconds.map { L10n.tf("env.sunshine.hours", $0 / 3600.0) } ?? "—",
            tint: .orange
        )
    }

    // MARK: - helpers

    private func isCurrentHour(_ t: Date) -> Bool {
        let cal = calendar
        let now = Date()
        return cal.component(.year, from: t) == cal.component(.year, from: now) &&
               cal.component(.month, from: t) == cal.component(.month, from: now) &&
               cal.component(.day, from: t) == cal.component(.day, from: now) &&
               cal.component(.hour, from: t) == cal.component(.hour, from: now)
    }

    private func uvColor(_ uv: Double) -> Color {
        switch uv {
        case ..<3:  return .green
        case ..<6:  return .yellow
        case ..<8:  return .orange
        case ..<11: return .red
        default:    return .purple
        }
    }

    private func uvCategoryLabel(_ uv: Double) -> String {
        switch uv {
        case ..<3:  return L10n.t("env.uv.low")
        case ..<6:  return L10n.t("env.uv.moderate")
        case ..<8:  return L10n.t("env.uv.high")
        case ..<11: return L10n.t("env.uv.veryhigh")
        default:    return L10n.t("env.uv.extreme")
        }
    }

    private func aqiColor(_ aqi: Int) -> Color {
        switch aqi {
        case ..<51:  return .green
        case ..<101: return .yellow
        case ..<151: return .orange
        case ..<201: return .red
        case ..<301: return .purple
        default:     return Color(red: 0.4, green: 0, blue: 0)
        }
    }

    private func aqiCategoryLabel(_ aqi: Int) -> String {
        switch aqi {
        case ..<51:  return L10n.t("env.aqi.good")
        case ..<101: return L10n.t("env.aqi.moderate")
        case ..<151: return L10n.t("env.aqi.usg")
        case ..<201: return L10n.t("env.aqi.unhealthy")
        case ..<301: return L10n.t("env.aqi.veryunhealthy")
        default:     return L10n.t("env.aqi.hazardous")
        }
    }

    private var hourStyle: Date.FormatStyle {
        var s = Date.FormatStyle()
            .hour(.defaultDigits(amPM: .omitted))
            .locale(state.effectiveLocale)
        s.timeZone = calendar.timeZone
        return s
    }
}

private struct BigValueBadge: View {
    let value: String
    let label: String
    let color: Color

    var body: some View {
        VStack(alignment: .center, spacing: 2) {
            Text(value)
                .font(.system(size: 26, weight: .semibold, design: .rounded))
                .foregroundStyle(color)
                .monospacedDigit()
            Text(label)
                .font(.caption2.weight(.medium))
                .foregroundStyle(color)
        }
        .frame(width: 86, height: 70)
        .background {
            RoundedRectangle(cornerRadius: 8)
                .fill(color.opacity(0.12))
        }
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(color.opacity(0.5), lineWidth: 0.5)
        )
    }
}

private struct EnvironmentTile: View {
    let icon: String
    let titleKey: String
    let value: String
    let tint: Color

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 14))
                .foregroundStyle(tint)
                .frame(width: 16)
            VStack(alignment: .leading, spacing: 1) {
                T(LocalizedStringKey(titleKey))
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                Text(value)
                    .font(.system(size: 12, weight: .medium))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

import SwiftUI
import Charts

struct TemperatureChart: View {
    let entries: [DailyForecast]
    let hourly: [HourlyForecast]
    var calendar: Calendar = Calendar(identifier: .gregorian)
    var unit: UnitSystem = .metric

    var body: some View {
        Chart {
            if !hourly.isEmpty {
                ForEach(sample3h(hourly)) { h in
                    if let t = h.temperatureC {
                        let v = TempFormat.value(t, in: unit)
                        LineMark(x: .value("t", h.time), y: .value("temp", v))
                            .interpolationMethod(.catmullRom)
                            .foregroundStyle(Color.orange)
                    }
                }
            } else {
                ForEach(entries) { e in
                    if let max = e.tempMaxC {
                        let v = TempFormat.value(max, in: unit)
                        LineMark(x: .value("d", e.date), y: .value("hi", v),
                                 series: .value("kind", "max"))
                            .foregroundStyle(Color.orange)
                            .symbol(.circle)
                    }
                    if let min = e.tempMinC {
                        let v = TempFormat.value(min, in: unit)
                        LineMark(x: .value("d", e.date), y: .value("lo", v),
                                 series: .value("kind", "min"))
                            .foregroundStyle(Color.orange.opacity(0.6))
                            .symbol(.circle)
                    }
                }
            }
        }
        .chartXAxis {
            AxisMarks(values: .stride(by: .hour, count: 6)) { value in
                if let date = value.as(Date.self) {
                    let hour = calendar.component(.hour, from: date)
                    if hour == 0 {
                        AxisGridLine(stroke: StrokeStyle(lineWidth: 0.8))
                            .foregroundStyle(Color.secondary.opacity(0.7))
                    } else {
                        AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [3, 3]))
                    }
                    AxisValueLabel(anchor: .top, verticalSpacing: 2) {
                        Text("\(hour)h").font(.caption2)
                    }
                }
            }
            AxisMarks(values: .stride(by: .day)) { value in
                AxisValueLabel(centered: true, anchor: .top, verticalSpacing: 16) {
                    if let date = value.as(Date.self) {
                        Text(date, format: dayStyle).font(.caption2)
                    }
                }
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading) { value in
                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [3, 3]))
                AxisValueLabel {
                    if let v = value.as(Double.self) {
                        Text("\(Int(v))\(TempFormat.unitSuffix(unit))").font(.caption2)
                    }
                }
            }
        }
        .chartXScale(domain: xDomain)
        .chartYScale(domain: yDomain)
        .chartPlotStyle { plot in
            plot.border(Color.secondary.opacity(0.5), width: 0.5)
        }
        .frame(height: 160)
        .accessibilityLabel("週間気温推移")
    }

    private var yDomain: ClosedRange<Double> {
        let temps: [Double]
        if !hourly.isEmpty {
            temps = hourly.compactMap { $0.temperatureC }
        } else {
            temps = entries.flatMap { [$0.tempMinC, $0.tempMaxC].compactMap { $0 } }
        }
        guard let lo = temps.min(), let hi = temps.max() else {
            return TempFormat.domain(0...35, in: unit)
        }
        let step: Double = unit == .imperial ? 10 : 5
        let pad: Double = unit == .imperial ? 5 : 3
        let lower = floor((lo - pad) / step) * step
        let upper = ceil((hi + pad) / step) * step
        return TempFormat.domain(lower...upper, in: unit)
    }

    private func sample3h(_ data: [HourlyForecast]) -> [HourlyForecast] {
        let cal = calendar
        return data.filter {
            let hour = cal.component(.hour, from: $0.time)
            return hour % 3 == 0
        }
    }

    private var xDomain: ClosedRange<Date> {
        let cal = calendar
        if let first = entries.first?.date, let last = entries.last?.date {
            let start = cal.startOfDay(for: first)
            let end = cal.date(byAdding: .day, value: 1, to: cal.startOfDay(for: last)) ?? last
            return start...end
        }
        if let first = hourly.first?.time, let last = hourly.last?.time {
            return first...last
        }
        let now = Date()
        return now...now.addingTimeInterval(7 * 86400)
    }

    private var dayStyle: Date.FormatStyle {
        var s = Date.FormatStyle()
            .month(.defaultDigits)
            .day(.defaultDigits)
            .locale(calendar.locale ?? .current)
        s.timeZone = calendar.timeZone
        return s
    }
}

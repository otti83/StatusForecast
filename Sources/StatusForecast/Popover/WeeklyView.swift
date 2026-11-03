import SwiftUI
import Charts

struct WeeklyView: View {
    @EnvironmentObject var state: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            chartSection
            Divider()
            cardRow
            Spacer(minLength: 0)
        }
    }

    private var weekly: [DailyForecast] { state.snapshot?.weekly ?? [] }
    private var location: Location? { state.snapshot?.location }

    @ViewBuilder
    private var chartSection: some View {
        if !weekly.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                T("section.weekly_temp")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                TemperatureChart(entries: weekly,
                                 hourly: state.snapshot?.hourly ?? [],
                                 calendar: location?.calendar ?? Calendar(identifier: .gregorian),
                                 unit: state.preferences.unitSystem)
                    .frame(height: 160)
            }
        } else {
            HStack {
                ProgressView().controlSize(.small)
                T("loading.weekly").font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private var cardRow: some View {
        HStack(alignment: .top, spacing: 4) {
            ForEach(Array(weekly.prefix(7).enumerated()), id: \.offset) { _, day in
                DayCard(day: day, calendar: cardCalendar, unit: state.preferences.unitSystem)
                    .frame(maxWidth: .infinity)
            }
        }
    }

    private var cardCalendar: Calendar {
        var c = location?.calendar ?? Calendar(identifier: .gregorian)
        c.locale = state.effectiveLocale
        return c
    }
}

private struct DayCard: View {
    let day: DailyForecast
    let calendar: Calendar
    let unit: UnitSystem

    var body: some View {
        VStack(spacing: 4) {
            Text(day.date, format: dayStyle)
                .font(.caption.weight(.bold))
                .frame(height: 14)
            Text("(\(day.date.formatted(weekdayStyle)))")
                .font(.caption2)
                .foregroundStyle(isWeekend ? weekendColor : .secondary)
                .frame(height: 12)
            WeatherSymbol(code: day.code, size: 22)
                .frame(height: 26)
            Text(WeatherCategoryMap.category(for: day.code).localizedLabel)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .frame(height: 14)
            Text(day.tempMaxC.map { TempFormat.intLabel($0, in: unit) } ?? "—")
                .foregroundStyle(.orange)
                .font(.caption.weight(.semibold))
                .frame(height: 14)
            Text(day.tempMinC.map { TempFormat.intLabel($0, in: unit) } ?? "—")
                .foregroundStyle(.blue)
                .font(.caption.weight(.semibold))
                .frame(height: 14)
            Text(day.pops.first?.percent.map { "\($0)%" } ?? "—")
                .font(.caption2.weight(.medium))
                .foregroundStyle(.blue)
                .frame(height: 12)
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 2)
        .frame(maxWidth: .infinity)
        .background {
            RoundedRectangle(cornerRadius: 6)
                .fill(isToday ? Color.accentColor.opacity(0.12) : Color.gray.opacity(0.08))
        }
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(isToday ? Color.accentColor : Color.gray.opacity(0.3),
                        lineWidth: isToday ? 1 : 0.5)
        )
    }

    private var isToday: Bool { calendar.isDateInToday(day.date) }

    private var isWeekend: Bool {
        let wd = calendar.component(.weekday, from: day.date)
        return wd == 1 || wd == 7
    }
    private var weekendColor: Color {
        let wd = calendar.component(.weekday, from: day.date)
        if wd == 1 { return .red }
        if wd == 7 { return .blue }
        return .secondary
    }

    private var dayStyle: Date.FormatStyle {
        var s = Date.FormatStyle()
            .month(.defaultDigits)
            .day(.defaultDigits)
            .locale(calendar.locale ?? .current)
        s.timeZone = calendar.timeZone
        return s
    }
    private var weekdayStyle: Date.FormatStyle {
        var s = Date.FormatStyle()
            .weekday(.abbreviated)
            .locale(calendar.locale ?? .current)
        s.timeZone = calendar.timeZone
        return s
    }
}

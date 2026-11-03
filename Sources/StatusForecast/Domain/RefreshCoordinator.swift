import Foundation

/// Single-source coordinator. Open-Meteo's forecast + air-quality endpoints
/// fan out in parallel, results merged into one WeatherSnapshot.
struct RefreshCoordinator {
    let openMeteo: OpenMeteoClient
    let airQuality: OpenMeteoAirQualityClient
    let grid: OpenMeteoGridClient

    init(openMeteo: OpenMeteoClient = OpenMeteoClient(),
         airQuality: OpenMeteoAirQualityClient = OpenMeteoAirQualityClient(),
         grid: OpenMeteoGridClient = OpenMeteoGridClient()) {
        self.openMeteo = openMeteo
        self.airQuality = airQuality
        self.grid = grid
    }

    func fetch(for location: Location) async throws -> WeatherSnapshot {
        var issues: [SourceIssue] = []

        async let forecastResult: OpenMeteoClient.Bundle = {
            do {
                return try await openMeteo.fetchAll(
                    latitude: location.latitude,
                    longitude: location.longitude,
                    timezone: location.timeZoneIdentifier,
                    days: 7,
                    includeCurrent: true,
                    includeDaily: true
                )
            } catch {
                return OpenMeteoClient.Bundle(hourly: [], current: nil, daily: [])
            }
        }()
        async let aqResult: AirQualitySnapshot? = {
            do {
                return try await airQuality.fetch(
                    latitude: location.latitude,
                    longitude: location.longitude,
                    timezone: location.timeZoneIdentifier
                )
            } catch {
                return nil
            }
        }()
        async let gridResult: [GridPoint] = {
            do {
                return try await grid.fetchGrid(
                    centerLat: location.latitude,
                    centerLon: location.longitude,
                    timezone: location.timeZoneIdentifier
                )
            } catch {
                return []
            }
        }()
        let (bundle, aq, gridPoints) = await (forecastResult, aqResult, gridResult)

        if bundle.hourly.isEmpty && bundle.daily.isEmpty {
            issues.append(SourceIssue(source: .openMeteo, message: L10n.t("issue.openMeteo")))
        }

        let cal = location.calendar
        let todayStart = cal.startOfDay(for: Date())
        let weekly = Array(bundle.daily.filter { $0.date >= todayStart }.prefix(7))

        let withPops = weekly.map { day -> DailyForecast in
            var d = day
            d = DailyForecast(
                date: d.date,
                code: d.code,
                tempMinC: d.tempMinC,
                tempMaxC: d.tempMaxC,
                pops: sixHourPops(for: d.date, hourly: bundle.hourly, calendar: cal),
                sunrise: d.sunrise,
                sunset: d.sunset,
                uvIndexMax: d.uvIndexMax,
                sunshineSeconds: d.sunshineSeconds
            )
            return d
        }
        let today = withPops.first
        let upcoming = Array(withPops.dropFirst())

        return WeatherSnapshot(
            location: location,
            fetchedAt: Date(),
            current: bundle.current,
            today: today,
            upcoming: upcoming,
            weekly: withPops,
            hourly: bundle.hourly,
            airQuality: aq,
            grid: gridPoints,
            issues: issues
        )
    }

    private func sixHourPops(for dayStart: Date, hourly: [HourlyForecast], calendar: Calendar) -> [PrecipChance] {
        var out: [PrecipChance] = []
        for slot in 0..<4 {
            guard let s = calendar.date(byAdding: .hour, value: slot * 6, to: dayStart),
                  let e = calendar.date(byAdding: .hour, value: slot * 6 + 6, to: dayStart) else { continue }
            let probs = hourly
                .filter { $0.time >= s && $0.time < e }
                .compactMap { $0.precipitationProbability }
            out.append(PrecipChance(start: s, end: e, percent: probs.max()))
        }
        return out
    }
}

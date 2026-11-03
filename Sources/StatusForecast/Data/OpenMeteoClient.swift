import Foundation

/// Open-Meteo client. Used in two modes:
/// - Japan locations: hourly only, supplementing JMA.
/// - Global locations: hourly + current + daily — the sole upstream.
struct OpenMeteoClient {
    enum OpenMeteoError: Error { case badPayload }

    struct Bundle: Sendable {
        let hourly: [HourlyForecast]
        let current: CurrentWeather?
        let daily: [DailyForecast]
    }

    private let http = HTTPClient.shared
    private let cache = DiskCache.shared

    func fetchHourly(latitude: Double, longitude: Double, timezone: String = "Asia/Tokyo", days: Int = 7) async throws -> [HourlyForecast] {
        try await fetchAll(latitude: latitude, longitude: longitude, timezone: timezone, days: days, includeCurrent: false, includeDaily: false).hourly
    }

    func fetchAll(latitude: Double,
                  longitude: Double,
                  timezone: String,
                  days: Int = 7,
                  includeCurrent: Bool,
                  includeDaily: Bool) async throws -> Bundle {
        var components = URLComponents(string: "https://api.open-meteo.com/v1/forecast")!
        var items: [URLQueryItem] = [
            URLQueryItem(name: "latitude",  value: String(format: "%.4f", latitude)),
            URLQueryItem(name: "longitude", value: String(format: "%.4f", longitude)),
            URLQueryItem(name: "hourly", value: [
                "temperature_2m",
                "relative_humidity_2m",
                "wind_speed_10m",
                "wind_direction_10m",
                "wind_gusts_10m",
                "precipitation",
                "precipitation_probability",
                "weather_code",
                "uv_index",
                "visibility",
                "cloud_cover",
                "cloud_cover_low",
                "cloud_cover_mid",
                "cloud_cover_high",
                "pressure_msl",
                "shortwave_radiation"
            ].joined(separator: ",")),
            URLQueryItem(name: "timezone", value: timezone),
            URLQueryItem(name: "forecast_days", value: String(days)),
            URLQueryItem(name: "wind_speed_unit", value: "ms")
        ]
        if includeCurrent {
            items.append(URLQueryItem(name: "current", value: [
                "temperature_2m",
                "relative_humidity_2m",
                "wind_speed_10m",
                "wind_direction_10m",
                "precipitation",
                "surface_pressure",
                "weather_code"
            ].joined(separator: ",")))
        }
        if includeDaily {
            items.append(URLQueryItem(name: "daily", value: [
                "weather_code",
                "temperature_2m_max",
                "temperature_2m_min",
                "precipitation_probability_max",
                "sunrise",
                "sunset",
                "uv_index_max",
                "sunshine_duration"
            ].joined(separator: ",")))
        }
        components.queryItems = items
        let url = components.url!
        let cacheKey = "openmeteo:v2:\(latitude),\(longitude),\(timezone),\(days),\(includeCurrent),\(includeDaily)"

        let data: Data
        do {
            let fetched = try await http.getJSON(url)
            await cache.write(cacheKey, data: fetched)
            data = fetched
        } catch {
            if let stale = await cache.readAny(cacheKey) {
                data = stale
            } else {
                throw error
            }
        }
        return try parse(data: data, timezone: timezone)
    }

    private func parse(data: Data, timezone: String) throws -> Bundle {
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw OpenMeteoError.badPayload
        }
        let tz = TimeZone(identifier: timezone) ?? TimeZone(identifier: "UTC")!

        let isoMinute = DateFormatter()
        isoMinute.locale = Locale(identifier: "en_US_POSIX")
        isoMinute.timeZone = tz
        isoMinute.dateFormat = "yyyy-MM-dd'T'HH:mm"

        let isoDay = DateFormatter()
        isoDay.locale = Locale(identifier: "en_US_POSIX")
        isoDay.timeZone = tz
        isoDay.dateFormat = "yyyy-MM-dd"

        // Hourly
        var hourly: [HourlyForecast] = []
        if let h = root["hourly"] as? [String: Any], let times = h["time"] as? [String] {
            let temps = (h["temperature_2m"] as? [Any]) ?? []
            let hums  = (h["relative_humidity_2m"] as? [Any]) ?? []
            let ws    = (h["wind_speed_10m"] as? [Any]) ?? []
            let wd    = (h["wind_direction_10m"] as? [Any]) ?? []
            let pr    = (h["precipitation"] as? [Any]) ?? []
            let pp    = (h["precipitation_probability"] as? [Any]) ?? []
            let wc    = (h["weather_code"] as? [Any]) ?? []
            let uv    = (h["uv_index"] as? [Any]) ?? []
            let vis   = (h["visibility"] as? [Any]) ?? []
            let cc    = (h["cloud_cover"] as? [Any]) ?? []
            let ccLo  = (h["cloud_cover_low"]  as? [Any]) ?? []
            let ccMd  = (h["cloud_cover_mid"]  as? [Any]) ?? []
            let ccHi  = (h["cloud_cover_high"] as? [Any]) ?? []
            let pres  = (h["pressure_msl"]    as? [Any]) ?? []
            let gust  = (h["wind_gusts_10m"]  as? [Any]) ?? []
            let rad   = (h["shortwave_radiation"] as? [Any]) ?? []
            for (i, ts) in times.enumerated() {
                guard let date = isoMinute.date(from: ts) else { continue }
                hourly.append(HourlyForecast(
                    time: date,
                    temperatureC: Self.d(temps, i),
                    humidity: Self.d(hums, i),
                    windSpeedMps: Self.d(ws, i),
                    windDirectionDeg: Self.d(wd, i),
                    precipitationMm: Self.d(pr, i),
                    precipitationProbability: Self.ii(pp, i),
                    weatherCode: Self.ii(wc, i),
                    uvIndex: Self.d(uv, i),
                    visibilityMeters: Self.d(vis, i),
                    cloudCoverPct: Self.d(cc, i),
                    cloudCoverLowPct: Self.d(ccLo, i),
                    cloudCoverMidPct: Self.d(ccMd, i),
                    cloudCoverHighPct: Self.d(ccHi, i),
                    pressureMslHPa: Self.d(pres, i),
                    windGustsMps: Self.d(gust, i),
                    shortwaveRadiation: Self.d(rad, i)
                ))
            }
        }

        // Current
        var current: CurrentWeather?
        if let c = root["current"] as? [String: Any] {
            let observedAt: Date = {
                if let s = c["time"] as? String, let d = isoMinute.date(from: s) { return d }
                return Date()
            }()
            current = CurrentWeather(
                observedAt: observedAt,
                temperatureC: c["temperature_2m"] as? Double,
                humidity: c["relative_humidity_2m"] as? Double,
                windDirectionDeg: c["wind_direction_10m"] as? Double,
                windSpeedMps: c["wind_speed_10m"] as? Double,
                precip1hMm: c["precipitation"] as? Double,
                pressureHPa: c["surface_pressure"] as? Double
            )
        }

        // Daily
        var daily: [DailyForecast] = []
        if let d = root["daily"] as? [String: Any], let times = d["time"] as? [String] {
            let codes = (d["weather_code"] as? [Any]) ?? []
            let maxs  = (d["temperature_2m_max"] as? [Any]) ?? []
            let mins  = (d["temperature_2m_min"] as? [Any]) ?? []
            let pops  = (d["precipitation_probability_max"] as? [Any]) ?? []
            let sunrises = (d["sunrise"] as? [String]) ?? []
            let sunsets  = (d["sunset"]  as? [String]) ?? []
            let uvMax    = (d["uv_index_max"] as? [Any]) ?? []
            let sunDur   = (d["sunshine_duration"] as? [Any]) ?? []
            for (i, ts) in times.enumerated() {
                guard let date = isoDay.date(from: ts) else { continue }
                let cal: Calendar = {
                    var c = Calendar(identifier: .gregorian)
                    c.timeZone = tz
                    return c
                }()
                let dayStart = cal.startOfDay(for: date)
                let dayEnd = cal.date(byAdding: .day, value: 1, to: dayStart) ?? dayStart
                let code = Self.ii(codes, i).map { WeatherCodeRef.wmo($0) } ?? .unknown
                let popPercent = Self.ii(pops, i)
                let sunrise: Date? = (i < sunrises.count) ? isoMinute.date(from: sunrises[i]) : nil
                let sunset:  Date? = (i < sunsets.count)  ? isoMinute.date(from: sunsets[i])  : nil
                daily.append(DailyForecast(
                    date: dayStart,
                    code: code,
                    tempMinC: Self.d(mins, i),
                    tempMaxC: Self.d(maxs, i),
                    pops: popPercent.map { [PrecipChance(start: dayStart, end: dayEnd, percent: $0)] } ?? [],
                    sunrise: sunrise, sunset: sunset,
                    uvIndexMax: Self.d(uvMax, i),
                    sunshineSeconds: Self.d(sunDur, i)
                ))
            }
        }
        return Bundle(hourly: hourly, current: current, daily: daily)
    }

    private static func d(_ arr: [Any], _ i: Int) -> Double? {
        guard i < arr.count else { return nil }
        if let v = arr[i] as? Double { return v }
        if let v = arr[i] as? Int { return Double(v) }
        if let v = arr[i] as? NSNumber { return v.doubleValue }
        return nil
    }
    private static func ii(_ arr: [Any], _ i: Int) -> Int? {
        guard i < arr.count else { return nil }
        if let v = arr[i] as? Int { return v }
        if let v = arr[i] as? Double { return Int(v) }
        if let v = arr[i] as? NSNumber { return v.intValue }
        return nil
    }
}

import Foundation

/// Open-Meteo Air Quality API — separate endpoint from the main forecast.
/// https://open-meteo.com/en/docs/air-quality-api
struct OpenMeteoAirQualityClient {
    enum AQError: Error { case badPayload }

    private let http = HTTPClient.shared
    private let cache = DiskCache.shared

    func fetch(latitude: Double, longitude: Double, timezone: String, days: Int = 2) async throws -> AirQualitySnapshot {
        var c = URLComponents(string: "https://air-quality-api.open-meteo.com/v1/air-quality")!
        c.queryItems = [
            URLQueryItem(name: "latitude",  value: String(format: "%.4f", latitude)),
            URLQueryItem(name: "longitude", value: String(format: "%.4f", longitude)),
            URLQueryItem(name: "hourly", value: "pm10,pm2_5,us_aqi"),
            URLQueryItem(name: "timezone", value: timezone),
            URLQueryItem(name: "forecast_days", value: String(days))
        ]
        let url = c.url!
        let key = "openmeteo-aq:v1:\(latitude),\(longitude),\(timezone),\(days)"

        let data: Data
        do {
            let fetched = try await http.getJSON(url)
            await cache.write(key, data: fetched)
            data = fetched
        } catch {
            if let stale = await cache.readAny(key) { data = stale }
            else { throw error }
        }

        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let h = root["hourly"] as? [String: Any],
              let times = h["time"] as? [String] else {
            throw AQError.badPayload
        }
        let pm10  = (h["pm10"]   as? [Any]) ?? []
        let pm25  = (h["pm2_5"]  as? [Any]) ?? []
        let aqi   = (h["us_aqi"] as? [Any]) ?? []

        let tz = TimeZone(identifier: timezone) ?? TimeZone(identifier: "UTC")!
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = tz
        f.dateFormat = "yyyy-MM-dd'T'HH:mm"

        var out: [AirQualityHourly] = []
        for (i, ts) in times.enumerated() {
            guard let date = f.date(from: ts) else { continue }
            out.append(AirQualityHourly(
                time: date,
                usAqi: ii(aqi, i),
                pm25: dd(pm25, i),
                pm10: dd(pm10, i)
            ))
        }
        return AirQualitySnapshot(hourly: out)
    }

    private func dd(_ a: [Any], _ i: Int) -> Double? {
        guard i < a.count else { return nil }
        if let v = a[i] as? Double { return v }
        if let v = a[i] as? Int { return Double(v) }
        if let v = a[i] as? NSNumber { return v.doubleValue }
        return nil
    }
    private func ii(_ a: [Any], _ i: Int) -> Int? {
        guard i < a.count else { return nil }
        if let v = a[i] as? Int { return v }
        if let v = a[i] as? Double { return Int(v) }
        if let v = a[i] as? NSNumber { return v.intValue }
        return nil
    }
}

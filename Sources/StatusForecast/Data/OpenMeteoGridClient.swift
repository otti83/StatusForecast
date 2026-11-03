import Foundation

/// Fetches a small lat/lon grid of current-weather samples around a center
/// point in one HTTP request, using Open-Meteo's multi-coordinate syntax.
///
/// Note: Open-Meteo snaps every requested coord to its internal model grid,
/// so the latitude/longitude values it returns are NOT the ones we asked for
/// and they aren't evenly spaced. We therefore keep the *requested* coords
/// as authoritative for grid-cell placement and only borrow the measurement
/// values (temperature, wind, …) from the response.
struct OpenMeteoGridClient {
    enum GridError: Error { case badPayload }

    private let http = HTTPClient.shared
    private let cache = DiskCache.shared

    func fetchGrid(centerLat: Double, centerLon: Double,
                   size: Int = 7, spacing: Double = 0.12,
                   timezone: String) async throws -> [GridPoint] {
        let half = (size - 1) / 2
        var requested: [(lat: Double, lon: Double)] = []
        for r in -half...half {
            for c in -half...half {
                requested.append((centerLat + Double(r) * spacing,
                                  centerLon + Double(c) * spacing))
            }
        }
        var url = URLComponents(string: "https://api.open-meteo.com/v1/forecast")!
        url.queryItems = [
            URLQueryItem(name: "latitude",
                         value: requested.map { String(format: "%.4f", $0.lat) }.joined(separator: ",")),
            URLQueryItem(name: "longitude",
                         value: requested.map { String(format: "%.4f", $0.lon) }.joined(separator: ",")),
            URLQueryItem(name: "current", value: "temperature_2m,wind_speed_10m,wind_direction_10m,weather_code"),
            URLQueryItem(name: "wind_speed_unit", value: "ms"),
            URLQueryItem(name: "timezone", value: timezone)
        ]
        let cacheKey = "openmeteo-grid:v2:\(centerLat),\(centerLon),\(size),\(spacing),\(timezone)"

        let data: Data
        do {
            let fetched = try await http.getJSON(url.url!)
            await cache.write(cacheKey, data: fetched)
            data = fetched
        } catch {
            if let stale = await cache.readAny(cacheKey) { data = stale } else { throw error }
        }

        let json = try JSONSerialization.jsonObject(with: data)
        let array: [[String: Any]]
        if let arr = json as? [[String: Any]] { array = arr }
        else if let obj = json as? [String: Any] { array = [obj] }
        else { throw GridError.badPayload }

        var out: [GridPoint] = []
        for (i, r) in array.enumerated() {
            guard i < requested.count, let cur = r["current"] as? [String: Any] else { continue }
            let req = requested[i]
            out.append(GridPoint(
                latitude: req.lat,
                longitude: req.lon,
                temperatureC: cur["temperature_2m"] as? Double,
                windSpeedMps: cur["wind_speed_10m"] as? Double,
                windDirectionDeg: cur["wind_direction_10m"] as? Double,
                weatherCode: cur["weather_code"] as? Int
            ))
        }
        return out
    }
}

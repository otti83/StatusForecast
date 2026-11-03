import Foundation

/// Open-Meteo Geocoding API — free, no API key, multi-language.
/// https://open-meteo.com/en/docs/geocoding-api
struct OpenMeteoGeocodingClient {
    struct Hit: Identifiable, Hashable, Sendable {
        let id: Int
        let name: String
        let admin1: String?
        let country: String?
        let countryCode: String?
        let latitude: Double
        let longitude: Double
        let timezone: String
        var displayName: String {
            [name, admin1, country].compactMap { $0?.isEmpty == false ? $0 : nil }.joined(separator: ", ")
        }
    }

    enum GeoError: Error { case badPayload }

    private let http = HTTPClient.shared

    func search(_ query: String, language: String) async throws -> [Hit] {
        var c = URLComponents(string: "https://geocoding-api.open-meteo.com/v1/search")!
        c.queryItems = [
            URLQueryItem(name: "name", value: query),
            URLQueryItem(name: "count", value: "20"),
            URLQueryItem(name: "language", value: language),
            URLQueryItem(name: "format", value: "json")
        ]
        let data = try await http.getJSON(c.url!)
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw GeoError.badPayload
        }
        let results = (root["results"] as? [[String: Any]]) ?? []
        return results.compactMap { r in
            guard let id = r["id"] as? Int,
                  let name = r["name"] as? String,
                  let lat = r["latitude"] as? Double,
                  let lon = r["longitude"] as? Double else { return nil }
            return Hit(
                id: id, name: name,
                admin1: r["admin1"] as? String,
                country: r["country"] as? String,
                countryCode: r["country_code"] as? String,
                latitude: lat, longitude: lon,
                timezone: (r["timezone"] as? String) ?? "UTC"
            )
        }
    }
}

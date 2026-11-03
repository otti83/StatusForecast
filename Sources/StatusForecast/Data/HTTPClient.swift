import Foundation

enum HTTPError: Error, CustomStringConvertible {
    case badStatus(Int)
    case empty
    case underlying(Error)

    var description: String {
        switch self {
        case .badStatus(let code): return "HTTP \(code)"
        case .empty: return "Empty response"
        case .underlying(let e):   return "\(e)"
        }
    }
}

actor HTTPClient {
    static let shared = HTTPClient()

    private let session: URLSession

    init() {
        let cfg = URLSessionConfiguration.default
        cfg.httpAdditionalHeaders = [
            "User-Agent": "StatusForecast/0.1 (+macOS)",
            "Accept": "application/json,*/*"
        ]
        cfg.timeoutIntervalForRequest = 15
        cfg.timeoutIntervalForResource = 30
        cfg.requestCachePolicy = .reloadIgnoringLocalCacheData
        cfg.waitsForConnectivity = true
        self.session = URLSession(configuration: cfg)
    }

    func getJSON(_ url: URL) async throws -> Data {
        let (data, response) = try await session.data(from: url)
        guard let http = response as? HTTPURLResponse else { throw HTTPError.empty }
        guard (200..<300).contains(http.statusCode) else { throw HTTPError.badStatus(http.statusCode) }
        guard !data.isEmpty else { throw HTTPError.empty }
        return data
    }

    func getText(_ url: URL) async throws -> String {
        let data = try await getJSON(url)
        return String(data: data, encoding: .utf8) ?? ""
    }
}

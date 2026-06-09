import Foundation

public enum PeroEndpoint: Equatable, Sendable {
    case health
    case places(PlacesQuery? = nil)
    case themes
    case theme(id: String)
    case events(region: String?, themeId: String?, activeOn: String?, limit: Int?)
    case search
    case recommendations

    var method: String {
        switch self {
        case .search, .recommendations:
            "POST"
        default:
            "GET"
        }
    }

    var path: String {
        switch self {
        case .health:
            "/api/health"
        case .places:
            "/api/places"
        case .themes:
            "/api/themes"
        case .theme(let id):
            "/api/themes/\(Self.percentEncodedPathSegment(id))"
        case .events:
            "/api/events"
        case .search:
            "/api/search"
        case .recommendations:
            "/api/recommendations"
        }
    }

    public func urlRequest(baseURL: URL) throws -> URLRequest {
        guard var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false) else {
            throw PeroAPIError.invalidBaseURL
        }
        components.path = normalizedPath(basePath: components.path, endpointPath: path)
        components.queryItems = queryItems

        guard let url = components.url else {
            throw PeroAPIError.invalidBaseURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        return request
    }

    private static func percentEncodedPathSegment(_ value: String) -> String {
        var allowed = CharacterSet.urlPathAllowed
        allowed.remove(charactersIn: "/")
        return value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
    }

    private var queryItems: [URLQueryItem]? {
        switch self {
        case .places(let query):
            guard let query else { return nil }
            var items: [URLQueryItem] = []
            if let latitude = query.latitude {
                items.append(URLQueryItem(name: "latitude", value: String(latitude)))
            }
            if let longitude = query.longitude {
                items.append(URLQueryItem(name: "longitude", value: String(longitude)))
            }
            if let radiusKm = query.radiusKm {
                items.append(URLQueryItem(name: "radiusKm", value: String(radiusKm)))
            }
            if let limit = query.limit {
                items.append(URLQueryItem(name: "limit", value: String(limit)))
            }
            if let includeTourApi = query.includeTourApi {
                items.append(URLQueryItem(name: "includeTourApi", value: String(includeTourApi)))
            }
            return items.isEmpty ? nil : items
        case .events(let region, let themeId, let activeOn, let limit):
            var items: [URLQueryItem] = []
            if let region, !region.isEmpty { items.append(URLQueryItem(name: "region", value: region)) }
            if let themeId, !themeId.isEmpty { items.append(URLQueryItem(name: "themeId", value: themeId)) }
            if let activeOn, !activeOn.isEmpty { items.append(URLQueryItem(name: "activeOn", value: activeOn)) }
            if let limit { items.append(URLQueryItem(name: "limit", value: String(limit))) }
            return items.isEmpty ? nil : items
        default:
            return nil
        }
    }

    private func normalizedPath(basePath: String, endpointPath: String) -> String {
        let cleanBase = basePath == "/" ? "" : basePath.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        if cleanBase.isEmpty {
            return endpointPath
        }
        return "/\(cleanBase)\(endpointPath)"
    }
}

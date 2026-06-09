import Foundation

public protocol HTTPTransport: Sendable {
    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse)
}

public struct URLSessionHTTPTransport: HTTPTransport {
    private let session: URLSession

    public init(session: URLSession = .shared) {
        self.session = session
    }

    public func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw PeroAPIError.invalidResponse
        }
        return (data, httpResponse)
    }
}

public protocol PeroAPIProviding: Sendable {
    func health() async throws -> HealthResponse
    func places() async throws -> PlacesResponse
    func places(query: PlacesQuery) async throws -> PlacesResponse
    func themes() async throws -> [ThemeSummary]
    func theme(id: String) async throws -> ThemeDetail
    func events(region: String?, themeId: String?, activeOn: String?, limit: Int?) async throws -> EventsResponse
    func search(_ request: SearchRequest) async throws -> SearchResponse
    func recommendations(_ request: RecommendationRequest) async throws -> RecommendationResponse
}

public extension PeroAPIProviding {
    func places(query: PlacesQuery) async throws -> PlacesResponse {
        try await places()
    }
}

public enum PeroAPIError: Error, Equatable, Sendable {
    case invalidBaseURL
    case invalidResponse
    case unacceptableStatus(Int)
}

public struct PeroAPIClient: PeroAPIProviding {
    private let baseURL: URL
    private let transport: HTTPTransport
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    public init(baseURL: URL, transport: HTTPTransport = URLSessionHTTPTransport()) {
        self.baseURL = baseURL
        self.transport = transport
        self.encoder = JSONEncoder()
        self.decoder = JSONDecoder.peroAPI
    }

    public func health() async throws -> HealthResponse {
        try await send(endpoint: .health)
    }

    public func places() async throws -> PlacesResponse {
        try await send(endpoint: .places())
    }

    public func places(query: PlacesQuery) async throws -> PlacesResponse {
        try await send(endpoint: .places(query))
    }

    public func themes() async throws -> [ThemeSummary] {
        try await send(endpoint: .themes)
    }

    public func theme(id: String) async throws -> ThemeDetail {
        try await send(endpoint: .theme(id: id))
    }

    public func events(region: String? = nil, themeId: String? = nil, activeOn: String? = nil, limit: Int? = nil) async throws -> EventsResponse {
        try await send(endpoint: .events(region: region, themeId: themeId, activeOn: activeOn, limit: limit))
    }

    public func search(_ request: SearchRequest) async throws -> SearchResponse {
        try await send(endpoint: .search, body: request)
    }

    public func recommendations(_ request: RecommendationRequest) async throws -> RecommendationResponse {
        try await send(endpoint: .recommendations, body: request)
    }

    private func send<Response: Decodable, Body: Encodable>(endpoint: PeroEndpoint, body: Body? = nil) async throws -> Response {
        var request = try endpoint.urlRequest(baseURL: baseURL)
        if let body {
            request.httpBody = try encoder.encode(body)
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        let (data, response) = try await transport.data(for: request)
        guard (200..<300).contains(response.statusCode) else {
            throw PeroAPIError.unacceptableStatus(response.statusCode)
        }
        return try decoder.decode(Response.self, from: data)
    }

    private func send<Response: Decodable>(endpoint: PeroEndpoint) async throws -> Response {
        try await send(endpoint: endpoint, body: Optional<String>.none)
    }
}

extension JSONDecoder {
    static var peroAPI: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let value = try container.decode(String.self)
            for options in ISO8601DateFormatter.peroDateFormatOptions {
                let formatter = ISO8601DateFormatter()
                formatter.formatOptions = options
                if let date = formatter.date(from: value) {
                    return date
                }
            }
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Expected ISO-8601 offset date string, got \(value)"
            )
        }
        return decoder
    }
}

private extension ISO8601DateFormatter {
    static var peroDateFormatOptions: [ISO8601DateFormatter.Options] {
        [
            [.withInternetDateTime, .withFractionalSeconds],
            [.withInternetDateTime]
        ]
    }
}

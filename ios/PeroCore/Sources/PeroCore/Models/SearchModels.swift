import Foundation

public enum SearchMode: String, Codable, Sendable, CaseIterable {
    case keyword = "KEYWORD"
    case vector = "VECTOR"
    case hybrid = "HYBRID"
}

public struct SearchRequest: Codable, Equatable, Sendable {
    public var query: String
    public var themeId: String?
    public var mode: SearchMode?
    public var latitude: Double?
    public var longitude: Double?
    public var radiusKm: Double?
    public var topK: Int?

    public init(
        query: String,
        themeId: String? = nil,
        mode: SearchMode? = nil,
        latitude: Double? = nil,
        longitude: Double? = nil,
        radiusKm: Double? = nil,
        topK: Int? = nil
    ) {
        self.query = query
        self.themeId = themeId
        self.mode = mode
        self.latitude = latitude
        self.longitude = longitude
        self.radiusKm = radiusKm
        self.topK = topK
    }
}

public struct RecommendationRequest: Codable, Equatable, Sendable {
    public var themeId: String?
    public var latitude: Double?
    public var longitude: Double?
    public var radiusKm: Double?

    public init(themeId: String? = nil, latitude: Double? = nil, longitude: Double? = nil, radiusKm: Double? = nil) {
        self.themeId = themeId
        self.latitude = latitude
        self.longitude = longitude
        self.radiusKm = radiusKm
    }
}

public struct SearchResponse: Decodable, Equatable, Sendable {
    public let query: String
    public let themeId: String?
    public let mode: SearchMode
    public let total: Int
    public let topK: Int
    public let generatedAt: Date
    public let source: SearchSourceMeta
    public let results: [PlaceResult]
}

public struct PlacesResponse: Decodable, Equatable, Sendable {
    public let source: SearchSourceMeta
    public let total: Int
    public let places: [PlaceListItem]
}

public struct EventsResponse: Decodable, Equatable, Sendable {
    public let generatedAt: Date
    public let total: Int
    public let events: [ThemeEvent]
}

public struct RecommendationResponse: Decodable, Equatable, Sendable {
    public let generatedAt: Date
    public let fallbackUsed: Bool
    public let nearbyPick: RecommendationCard?
    public let mealPick: RecommendationCard?
    public let dateCourse: DateCourse?
}

public struct SearchSourceMeta: Decodable, Equatable, Sendable {
    public let providerId: String
    public let providerName: String
    public let status: String
    public let generatedAt: Date
    public let count: Int
}

public struct HealthResponse: Decodable, Equatable, Sendable {
    public let service: String
    public let status: String
    public let time: Date
}

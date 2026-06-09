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
    public var north: Double?
    public var south: Double?
    public var east: Double?
    public var west: Double?
    public var zoom: Double?
    public var density: String?
    public var category: String?
    public var mode: String?
    public var limit: Int?
    public var recentPlaceIds: [String]?
    public var includeTourApi: Bool?

    public init(
        themeId: String? = nil,
        latitude: Double? = nil,
        longitude: Double? = nil,
        radiusKm: Double? = nil,
        north: Double? = nil,
        south: Double? = nil,
        east: Double? = nil,
        west: Double? = nil,
        zoom: Double? = nil,
        density: String? = nil,
        category: String? = nil,
        mode: String? = nil,
        limit: Int? = nil,
        recentPlaceIds: [String]? = nil,
        includeTourApi: Bool? = nil
    ) {
        self.themeId = themeId
        self.latitude = latitude
        self.longitude = longitude
        self.radiusKm = radiusKm
        self.north = north
        self.south = south
        self.east = east
        self.west = west
        self.zoom = zoom
        self.density = density
        self.category = category
        self.mode = mode
        self.limit = limit
        self.recentPlaceIds = recentPlaceIds
        self.includeTourApi = includeTourApi
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
    public let generatedAt: Date?
    public let fallbackUsed: Bool?
    public let randomScope: String?
    public let total: Int
    public let places: [PlaceListItem]

    public init(source: SearchSourceMeta, generatedAt: Date? = nil, fallbackUsed: Bool? = nil, randomScope: String? = nil, total: Int, places: [PlaceListItem]) {
        self.source = source
        self.generatedAt = generatedAt
        self.fallbackUsed = fallbackUsed
        self.randomScope = randomScope
        self.total = total
        self.places = places
    }
}

public struct PlacesQuery: Equatable, Sendable {
    public let latitude: Double?
    public let longitude: Double?
    public let radiusKm: Double?
    public let north: Double?
    public let south: Double?
    public let east: Double?
    public let west: Double?
    public let zoom: Double?
    public let density: String?
    public let category: String?
    public let mode: String?
    public let source: String?
    public let activeFestival: Bool?
    public let limit: Int?
    public let includeTourApi: Bool?

    public init(
        latitude: Double? = nil,
        longitude: Double? = nil,
        radiusKm: Double? = nil,
        north: Double? = nil,
        south: Double? = nil,
        east: Double? = nil,
        west: Double? = nil,
        zoom: Double? = nil,
        density: String? = nil,
        category: String? = nil,
        mode: String? = nil,
        source: String? = nil,
        activeFestival: Bool? = nil,
        limit: Int? = nil,
        includeTourApi: Bool? = nil
    ) {
        self.latitude = latitude
        self.longitude = longitude
        self.radiusKm = radiusKm
        self.north = north
        self.south = south
        self.east = east
        self.west = west
        self.zoom = zoom
        self.density = density
        self.category = category
        self.mode = mode
        self.source = source
        self.activeFestival = activeFestival
        self.limit = limit
        self.includeTourApi = includeTourApi
    }
}

public struct EventsResponse: Decodable, Equatable, Sendable {
    public let generatedAt: Date
    public let total: Int
    public let events: [ThemeEvent]
}

public struct RecommendationResponse: Decodable, Equatable, Sendable {
    public let generatedAt: Date
    public let source: SearchSourceMeta
    public let fallbackUsed: Bool
    public let randomScope: String
    public let nearbyPick: RecommendationCard?
    public let mealPick: RecommendationCard?
    public let dateCourse: DateCourse?
}

public struct SearchSourceMeta: Decodable, Equatable, Sendable {
    public let providerId: String
    public let providerName: String
    public let status: String
    public let generatedAt: Date?
    public let count: Int

    public init(providerId: String, providerName: String, status: String, generatedAt: Date?, count: Int) {
        self.providerId = providerId
        self.providerName = providerName
        self.status = status
        self.generatedAt = generatedAt
        self.count = count
    }
}

public struct HealthResponse: Decodable, Equatable, Sendable {
    public let service: String
    public let status: String
    public let time: Date
}

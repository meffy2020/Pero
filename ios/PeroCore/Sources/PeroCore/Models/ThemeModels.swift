import Foundation

public struct ThemeSummary: Decodable, Equatable, Sendable, Identifiable {
    public var id: String { themeId }

    public let themeId: String
    public let title: String
    public let scope: String
    public let source: String
    public let badge: String
    public let summary: String
    public let heroPlaces: [ThemePlace]
    public let heroEventCount: Int
}

public struct ThemeDetail: Decodable, Equatable, Sendable, Identifiable {
    public var id: String { themeId }

    public let themeId: String
    public let title: String
    public let scope: String
    public let source: String
    public let badge: String
    public let summary: String
    public let generatedAt: Date
    public let center: ThemeCenter
    public let smartSeoulLayerEnabled: Bool
    public let sourceAttributions: [String]
    public let places: [ThemePlace]
    public let events: [ThemeEvent]
}

public struct ThemeCenter: Decodable, Equatable, Sendable {
    public let latitude: Double
    public let longitude: Double
}

public struct ThemePlace: Decodable, Equatable, Sendable, Identifiable {
    public let id: String
    public let name: String
    public let category: String
    public let district: String
    public let address: String
    public let roadAddress: String
    public let summary: String
    public let tags: [String]
    public let themeTags: [String]
    public let latitude: Double
    public let longitude: Double
    public let sourceAttribution: String
    public let reason: String
    public let tourApi: TourAPI?
}

public struct ThemeEvent: Decodable, Equatable, Sendable, Identifiable {
    public let id: String
    public let title: String
    public let status: String
    public let startDate: String
    public let endDate: String
    public let periodLabel: String
    public let district: String
    public let venue: String
    public let latitude: Double
    public let longitude: Double
    public let sourceAttribution: String
    public let summary: String
    public let themeId: String
    public let relatedPlaceId: String?
}

public struct RecommendationCard: Decodable, Equatable, Sendable {
    public let key: String
    public let title: String
    public let description: String
    public let place: RecommendationPlace?
}

public struct DateCourse: Decodable, Equatable, Sendable {
    public let title: String
    public let description: String
    public let stops: [DateCourseStop]
}

public struct DateCourseStop: Decodable, Equatable, Sendable {
    public let slot: String
    public let place: RecommendationPlace?
}

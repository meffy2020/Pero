import Foundation

public enum PeroAPIProviderFactory {
    public static func live(baseURL: URL) -> PeroAPIProviding {
        PeroAPIClient(baseURL: baseURL)
    }

    public static func preview() -> PeroAPIProviding {
        PreviewPeroAPIProvider()
    }
}

public struct PreviewPeroAPIProvider: PeroAPIProviding {
    public init() {}

    public func health() async throws -> HealthResponse {
        HealthResponse(service: "pero-backend", status: "ok", time: Date(timeIntervalSince1970: 0))
    }

    public func places() async throws -> PlacesResponse {
        PlacesResponse(source: source, total: previewPlaces.count, places: previewPlaces)
    }

    public func themes() async throws -> [ThemeSummary] {
        [
            ThemeSummary(
                themeId: "date-course",
                title: "오늘 데이트 코스",
                scope: "서울",
                source: "preview",
                badge: "MVP",
                summary: "반려동물과 함께 둘러보기 좋은 미리보기 코스입니다.",
                heroPlaces: [],
                heroEventCount: 0
            )
        ]
    }

    public func theme(id: String) async throws -> ThemeDetail {
        ThemeDetail(
            themeId: id,
            title: "미리보기 테마",
            scope: "서울",
            source: "preview",
            badge: "MVP",
            summary: "SwiftUI 화면 연결용 미리보기 데이터입니다.",
            generatedAt: Date(timeIntervalSince1970: 0),
            center: ThemeCenter(latitude: 37.5665, longitude: 126.9780),
            smartSeoulLayerEnabled: false,
            sourceAttributions: ["Preview"],
            places: [],
            events: []
        )
    }

    public func events(region: String?, themeId: String?, activeOn: String?, limit: Int?) async throws -> EventsResponse {
        EventsResponse(generatedAt: Date(timeIntervalSince1970: 0), total: 0, events: [])
    }

    public func search(_ request: SearchRequest) async throws -> SearchResponse {
        SearchResponse(
            query: request.query,
            themeId: request.themeId,
            mode: request.mode ?? .hybrid,
            total: 1,
            topK: request.topK ?? 8,
            generatedAt: Date(timeIntervalSince1970: 0),
            source: source,
            results: [previewResult]
        )
    }

    public func recommendations(_ request: RecommendationRequest) async throws -> RecommendationResponse {
        RecommendationResponse(
            generatedAt: Date(timeIntervalSince1970: 0),
            fallbackUsed: true,
            nearbyPick: nil,
            mealPick: nil,
            dateCourse: nil
        )
    }

    private var source: SearchSourceMeta {
        SearchSourceMeta(
            providerId: "preview",
            providerName: "iOS 미리보기 데이터",
            status: "loaded",
            generatedAt: Date(timeIntervalSince1970: 0),
            count: previewPlaces.count
        )
    }

    private var previewPlaces: [PlaceListItem] {
        [
            PlaceListItem(
                id: "preview-seoul-park",
                name: "서울 반려 산책 공원",
                category: "공원",
                district: "중구",
                address: "서울특별시 중구",
                roadAddress: "서울특별시 중구 세종대로",
                summary: "MVP 화면 상태 검증을 위한 미리보기 장소입니다.",
                tags: ["반려동물", "산책"],
                themeTags: ["date-course"],
                latitude: 37.5665,
                longitude: 126.9780,
                sourceAttribution: "Preview",
                tourApi: nil
            )
        ]
    }

    private var previewResult: PlaceResult {
        PlaceResult(
            id: "preview-seoul-park",
            name: "서울 반려 산책 공원",
            category: "공원",
            district: "중구",
            address: "서울특별시 중구",
            roadAddress: "서울특별시 중구 세종대로",
            summary: "MVP 화면 상태 검증을 위한 미리보기 장소입니다.",
            tags: ["반려동물", "산책"],
            themeTags: ["date-course"],
            latitude: 37.5665,
            longitude: 126.9780,
            sourceAttribution: "Preview",
            distanceKm: nil,
            evidence: "preview",
            keywordScore: 1,
            vectorScore: 0,
            featureScore: 0,
            geoScore: 0,
            finalScore: 1,
            tourApi: nil
        )
    }
}

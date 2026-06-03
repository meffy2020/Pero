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
            nearbyPick: RecommendationCard(
                key: "nearby",
                title: "가까운 산책 추천",
                description: "현재 위치에서 이동 부담이 낮고 바로 설명 가능한 장소입니다.",
                place: previewRecommendationPlaces[0]
            ),
            mealPick: RecommendationCard(
                key: "meal",
                title: "가벼운 식사 후 이동",
                description: "짧은 식사와 주변 산책을 묶어 지금 가기 좋습니다.",
                place: previewRecommendationPlaces[1]
            ),
            dateCourse: DateCourse(
                title: "지금 출발 코스",
                description: "실내 전시와 산책을 함께 묶은 설명 우선 코스입니다.",
                stops: [
                    DateCourseStop(slot: "1차 확인", place: previewRecommendationPlaces[2]),
                    DateCourseStop(slot: "2차 산책", place: previewRecommendationPlaces[0])
                ]
            )
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
                summary: "현재 위치 기준 산책 동선이 짧은 미리보기 장소입니다.",
                tags: ["반려동물", "산책"],
                themeTags: ["go-now", "date-course"],
                latitude: 37.5665,
                longitude: 126.9780,
                sourceAttribution: "Preview",
                tourApi: nil
            ),
            PlaceListItem(
                id: "preview-market",
                name: "도심 간편 식당가",
                category: "음식점",
                district: "중구",
                address: "서울특별시 중구",
                roadAddress: "서울특별시 중구 무교로",
                summary: "식사 후 이동하기 쉬운 미리보기 장소입니다.",
                tags: ["식사", "도보"],
                themeTags: ["go-now"],
                latitude: 37.5677,
                longitude: 126.9794,
                sourceAttribution: "Preview",
                tourApi: nil
            ),
            PlaceListItem(
                id: "preview-gallery",
                name: "시청 인근 전시 공간",
                category: "전시",
                district: "중구",
                address: "서울특별시 중구",
                roadAddress: "서울특별시 중구 세종대로",
                summary: "날씨 영향을 덜 받는 실내 미리보기 장소입니다.",
                tags: ["실내", "전시"],
                themeTags: ["go-now"],
                latitude: 37.5651,
                longitude: 126.9759,
                sourceAttribution: "Preview",
                tourApi: nil
            )
        ]
    }

    private var previewRecommendationPlaces: [RecommendationPlace] {
        [
            RecommendationPlace(
                id: "preview-seoul-park",
                name: "서울 반려 산책 공원",
                category: "공원",
                district: "중구",
                roadAddress: "서울특별시 중구 세종대로",
                summary: "현재 위치 기준 산책 동선이 짧은 미리보기 장소입니다.",
                tags: ["산책", "반려동물"],
                themeTags: ["go-now"],
                latitude: 37.5665,
                longitude: 126.9780,
                sourceAttribution: "Preview",
                distanceKm: 0.8,
                reason: "현재 위치에서 가깝고 야외 동선이 단순합니다.",
                tourApi: nil
            ),
            RecommendationPlace(
                id: "preview-market",
                name: "도심 간편 식당가",
                category: "음식점",
                district: "중구",
                roadAddress: "서울특별시 중구 무교로",
                summary: "식사 후 이동하기 쉬운 미리보기 장소입니다.",
                tags: ["식사", "도보"],
                themeTags: ["go-now"],
                latitude: 37.5677,
                longitude: 126.9794,
                sourceAttribution: "Preview",
                distanceKm: 1.1,
                reason: "짧은 식사와 다음 장소 이동을 함께 설명할 수 있습니다.",
                tourApi: nil
            ),
            RecommendationPlace(
                id: "preview-gallery",
                name: "시청 인근 전시 공간",
                category: "전시",
                district: "중구",
                roadAddress: "서울특별시 중구 세종대로",
                summary: "날씨 영향을 덜 받는 실내 미리보기 장소입니다.",
                tags: ["실내", "전시"],
                themeTags: ["go-now"],
                latitude: 37.5651,
                longitude: 126.9759,
                sourceAttribution: "Preview",
                distanceKm: 1.4,
                reason: "비가 와도 설명 가능한 실내 동선을 제공합니다.",
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

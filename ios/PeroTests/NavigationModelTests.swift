import Foundation
import Testing
@testable import Pero
@testable import PeroCore

struct NavigationModelTests {
    @Test func routesCarryStableRecommendationIDs() {
        let card = RecommendationCardModel.sample
        let routes: Set<AppRoute> = [.recommendationDetail(cardID: card.id), .mapFocus(cardID: card.id)]
        #expect(routes.count == 2)
        #expect(AppRoute.recommendationDetail(cardID: card.id).cardID == "preview-seoul-park")
        #expect(AppRoute.mapFocus(cardID: card.id).cardID == "preview-seoul-park")
    }

    @Test func recommendationStatesExposeKoreanCopy() {
        #expect(RecommendationState.ready.title == "현재 위치 준비")
        #expect(RecommendationState.loading.title == "지금 갈 곳 찾는 중")
        #expect(RecommendationState.results.title == "추천 결과")
        #expect(RecommendationState.empty.title == "추천 후보 없음")
        #expect(RecommendationState.error("x").title == "연결 확인 필요")
    }

    @Test func homeMapKoreanCopyExplainsViewportRandomPick() {
        #expect(HomeMapKoreanCopy.heroSubtitle.contains("현재 보고 있는 지도 안 후보"))
        #expect(HomeMapKoreanCopy.randomPickCTA == "이 화면에서 랜덤 픽")
        #expect(HomeMapKoreanCopy.randomPickHint.contains("현재 화면의 추천 후보"))
        #expect(HomeMapKoreanCopy.mapPreviewEyebrow == "현재 화면 후보")
        #expect(HomeMapKoreanCopy.reasonCTA == "왜 뽑혔는지 보기")
    }

    @Test func recommendationNormalizerPrefersCardsBeforeCourseStopsAndLimitsToThree() {
        let response = RecommendationResponse.previewForTests
        let cards = RecommendationViewModel.normalize(response: response)
        #expect(cards.map(\.id) == ["preview-seoul-park", "preview-market", "preview-gallery"])
        #expect(cards.map(\.subtitle) == ["랜덤 장소 추천", "식당 추천", "랜덤 코스 추천"])
        #expect(cards.count == 3)
        #expect(cards.first?.reason.contains("현재 위치") == true)
    }

    @Test @MainActor func viewModelKeepsSlotIdentityWhenEarlierRecommendationIsMissing() async {
        let provider = CapturingRecommendationProvider(response: .missingNearbyForTests)
        let locationProvider = StaticLocationProvider(latitude: 35.1796, longitude: 129.0756)
        let viewModel = RecommendationViewModel(provider: provider, locationProvider: locationProvider)

        await viewModel.loadGoNowRecommendations()

        #expect(viewModel.card(forSlotTitle: "랜덤 장소 추천") == nil)
        #expect(viewModel.card(forSlotTitle: "식당 추천")?.id == "preview-market")
        #expect(viewModel.card(forSlotTitle: "랜덤 코스 추천")?.id == "preview-gallery")
    }


    @Test @MainActor func viewModelRequestsRecommendationsFromCurrentLocation() async {
        let provider = CapturingRecommendationProvider()
        let locationProvider = StaticLocationProvider(latitude: 35.1796, longitude: 129.0756)
        let viewModel = RecommendationViewModel(provider: provider, locationProvider: locationProvider)

        await viewModel.loadGoNowRecommendations()

        #expect(provider.lastRequest?.themeId == "go-now")
        #expect(provider.lastRequest?.latitude == 35.1796)
        #expect(provider.lastRequest?.longitude == 129.0756)
        #expect(provider.recommendationCallCount == 1)
        #expect(provider.searchCallCount == 0)
        #expect(provider.lastRequest?.radiusKm == 3)
        #expect(viewModel.cards.count == 3)
        #expect(viewModel.locationLabel.contains("35.1796") == true)
    }

    @Test @MainActor func viewModelKeepsLastCardsAddressableAfterTransientReloadFailure() async {
        let provider = CapturingRecommendationProvider()
        let locationProvider = StaticLocationProvider(latitude: 35.1796, longitude: 129.0756)
        let viewModel = RecommendationViewModel(provider: provider, locationProvider: locationProvider)

        await viewModel.loadGoNowRecommendations()
        let firstCardID = try! #require(viewModel.cards.first?.id)

        provider.shouldFailRecommendations = true
        await viewModel.loadGoNowRecommendations()

        #expect(viewModel.card(for: firstCardID)?.id == firstCardID)
        #expect(viewModel.cards.isEmpty == false)
        if case .error = viewModel.state {
            #expect(true)
        } else {
            #expect(Bool(false), "transient failure should be visible without orphaning the last recommendation")
        }
    }

    @Test @MainActor func viewModelStartsAsSpontaneousRecommendationSurface() {
        let viewModel = RecommendationViewModel(
            provider: CapturingRecommendationProvider(),
            locationProvider: StaticLocationProvider.preview
        )

        #expect(viewModel.state == .ready)
        #expect(viewModel.cards.isEmpty)
        #expect(viewModel.locationLabel == "현재 위치 확인 전")
    }

    @Test func runtimeConfigurationUsesLiveProviderUnlessPreviewIsExplicit() {
        let liveProvider = AppRuntimeConfiguration.makeProvider(environment: ["PERO_API_BASE_URL": "http://localhost:8080"])
        let previewProvider = AppRuntimeConfiguration.makeProvider(environment: ["PERO_USE_PREVIEW": "1"])

        #expect(String(describing: type(of: liveProvider)).contains("PeroAPIClient"))
        #expect(previewProvider is PreviewPeroAPIProvider)
    }

    @Test func previewRuntimeUsesStaticLocationProviderForSimulatorDemos() {
        let liveLocationProvider = AppRuntimeConfiguration.makeLocationProvider(environment: [:])
        let previewLocationProvider = AppRuntimeConfiguration.makeLocationProvider(environment: ["PERO_USE_PREVIEW": "1"])

        #expect(liveLocationProvider is CoreLocationProvider)
        #expect(previewLocationProvider is StaticLocationProvider)
    }

    @Test func invalidRuntimeBaseURLIsNotPreviewFallback() {
        #expect(throws: Never.self) {
            let baseURL = try #require(AppRuntimeConfiguration.resolvedLiveBaseURL("http://localhost:8080"))
            #expect(baseURL.host == "localhost")
        }
        #expect(AppRuntimeConfiguration.resolvedLiveBaseURL("ftp://localhost:8080") == nil)
        #expect(AppRuntimeConfiguration.resolvedLiveBaseURL("not a url") == nil)
    }
}

private extension RecommendationCardModel {
    static let sample = RecommendationCardModel(
        id: "preview-seoul-park",
        title: "서울 반려 산책 공원",
        subtitle: "가까운 산책 추천",
        reason: "현재 위치에서 이동 부담이 낮고 설명 가능한 장소입니다.",
        category: "공원",
        district: "중구",
        roadAddress: "서울특별시 중구 세종대로",
        latitude: 37.5665,
        longitude: 126.9780,
        distanceLabel: "0.8km",
        sourceAttribution: "Preview",
        tags: ["산책", "반려동물"]
    )
}

private extension RecommendationResponse {
    static let previewForTests = RecommendationResponse(
        generatedAt: Date(timeIntervalSince1970: 0),
        fallbackUsed: true,
        nearbyPick: RecommendationCard(
            key: "nearby",
            title: "가까운 산책 추천",
            description: "현재 위치에서 이동 부담이 낮고 바로 설명 가능한 장소입니다.",
            place: places[0]
        ),
        mealPick: RecommendationCard(
            key: "meal",
            title: "가벼운 식사 후 이동",
            description: "짧은 식사와 주변 산책을 묶어 지금 가기 좋습니다.",
            place: places[1]
        ),
        dateCourse: DateCourse(
            title: "지금 출발 코스",
            description: "실내 전시와 산책을 함께 묶은 설명 우선 코스입니다.",
            stops: [
                DateCourseStop(slot: "1차 확인", place: places[2]),
                DateCourseStop(slot: "중복 제거 확인", place: places[0])
            ]
        )
    )

    private static let places = [
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

    static let missingNearbyForTests = RecommendationResponse(
        generatedAt: Date(timeIntervalSince1970: 0),
        fallbackUsed: false,
        nearbyPick: nil,
        mealPick: RecommendationCard(
            key: "meal",
            title: "가벼운 식사 후 이동",
            description: "짧은 식사와 주변 산책을 묶어 지금 가기 좋습니다.",
            place: places[1]
        ),
        dateCourse: DateCourse(
            title: "지금 출발 코스",
            description: "실내 전시와 산책을 함께 묶은 설명 우선 코스입니다.",
            stops: [
                DateCourseStop(slot: "1차 확인", place: places[2])
            ]
        )
    )
}


private final class CapturingRecommendationProvider: PeroAPIProviding, @unchecked Sendable {
    private(set) var lastRequest: RecommendationRequest?
    private(set) var recommendationCallCount = 0
    private(set) var searchCallCount = 0
    var shouldFailRecommendations = false
    private let response: RecommendationResponse

    init(response: RecommendationResponse = .previewForTests) {
        self.response = response
    }

    func health() async throws -> HealthResponse {
        HealthResponse(service: "test", status: "ok", time: Date(timeIntervalSince1970: 0))
    }

    func places() async throws -> PlacesResponse {
        PlacesResponse(source: SearchSourceMeta(providerId: "test", providerName: "test", status: "loaded", generatedAt: Date(timeIntervalSince1970: 0), count: 0), total: 0, places: [])
    }

    func themes() async throws -> [ThemeSummary] { [] }

    func theme(id: String) async throws -> ThemeDetail {
        ThemeDetail(themeId: id, title: "test", scope: "test", source: "test", badge: "test", summary: "test", generatedAt: Date(timeIntervalSince1970: 0), center: ThemeCenter(latitude: 0, longitude: 0), smartSeoulLayerEnabled: false, sourceAttributions: [], places: [], events: [])
    }

    func events(region: String?, themeId: String?, activeOn: String?, limit: Int?) async throws -> EventsResponse {
        EventsResponse(generatedAt: Date(timeIntervalSince1970: 0), total: 0, events: [])
    }

    func search(_ request: SearchRequest) async throws -> SearchResponse {
        searchCallCount += 1
        return SearchResponse(query: request.query, themeId: request.themeId, mode: request.mode ?? .hybrid, total: 0, topK: request.topK ?? 0, generatedAt: Date(timeIntervalSince1970: 0), source: SearchSourceMeta(providerId: "test", providerName: "test", status: "loaded", generatedAt: Date(timeIntervalSince1970: 0), count: 0), results: [])
    }

    func recommendations(_ request: RecommendationRequest) async throws -> RecommendationResponse {
        recommendationCallCount += 1
        lastRequest = request
        if shouldFailRecommendations {
            throw URLError(.notConnectedToInternet)
        }
        return response
    }
}

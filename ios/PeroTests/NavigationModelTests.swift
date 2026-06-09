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

    @Test func recommendationCardMapFirstHelpersExposeStablePresentationMetadata() throws {
        let card = RecommendationCardModel.sample

        #expect(card.mapFirstSummaryChips == ["0.8km", "중구", "공원"])
        #expect(card.mapFirstAccessibilitySummary == "가까운 산책 추천, 서울 반려 산책 공원, 0.8km, 중구, 공원")
        #expect(card.mapPrimaryCTATitle == "지도에서 장소 뽑기")

        let url = try #require(card.appleMapsURL)
        let components = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false))
        let queryItems = components.queryItems ?? []
        #expect(components.host == "maps.apple.com")
        #expect(queryItems.contains(URLQueryItem(name: "ll", value: "37.5665,126.978")))
        #expect(queryItems.contains(URLQueryItem(name: "q", value: "서울 반려 산책 공원")))
    }

    @Test func recommendationSlotKindDrivesMapPrimaryCTACopy() {
        let place = RecommendationCardModel.sample.with(
            title: "조용한 산책 공원",
            subtitle: "랜덤 장소 추천",
            category: "공원"
        )
        let restaurant = RecommendationCardModel.sample.with(
            title: "도심 간편 식당가",
            subtitle: "식당 추천",
            category: "음식점"
        )
        let festival = RecommendationCardModel.sample.with(
            title: "서울 야간 축제",
            subtitle: "축제 추천",
            category: "행사/공연/축제"
        )

        #expect(place.randomSlotKind == .attraction)
        #expect(place.mapPrimaryCTATitle == "지도에서 장소 뽑기")
        #expect(restaurant.randomSlotKind == .restaurant)
        #expect(restaurant.mapPrimaryCTATitle == "지도에서 식당 뽑기")
        #expect(festival.randomSlotKind == .festival)
        #expect(festival.mapPrimaryCTATitle == "지도에서 축제 뽑기")
    }

    @Test func recommendationCardCategoryIconsStayPresentationOnly() {
        #expect(RecommendationCardModel.sample.with(category: "음식점").categoryIconName == "fork.knife.circle.fill")
        #expect(RecommendationCardModel.sample.with(category: "전시").categoryIconName == "building.columns.circle.fill")
        #expect(RecommendationCardModel.sample.with(category: "공원").categoryIconName == "leaf.circle.fill")
    }

    @Test func recommendationStatesExposeKoreanCopy() {
        #expect(RecommendationState.ready.title == "지도 준비")
        #expect(RecommendationState.loading.title == "지금 갈 곳 찾는 중")
        #expect(RecommendationState.results.title == "추천 결과")
        #expect(RecommendationState.empty.title == "추천 후보 없음")
        #expect(RecommendationState.error("x").title == "연결 확인 필요")
    }

    @Test func homeMapKoreanCopyExplainsViewportRandomPick() {
        #expect(HomeMapKoreanCopy.readyMessage.contains("지도 후보"))
        #expect(HomeMapKoreanCopy.loadingMessage == "지도 안 후보를 불러오고 있습니다.")
        #expect(HomeMapKoreanCopy.emptyMessage.contains("추천 후보"))
    }

    @Test func recommendationNormalizerPrefersCardsBeforeCourseStopsAndLimitsToThree() {
        let response = RecommendationResponse.previewForTests
        let cards = RecommendationViewModel.normalize(response: response)
        #expect(cards.map(\.id) == ["preview-seoul-park", "preview-market", "preview-gallery"])
        #expect(cards.map(\.subtitle) == ["랜덤 장소 추천", "식당 추천", "랜덤 코스 추천"])
        #expect(cards.count == 3)
        #expect(cards.first?.reason.contains("현재 위치") == true)
    }


    @Test func placePoolNormalizerTurnsPlacesIntoMapPins() {
        let cards = RecommendationViewModel.normalize(places: PlaceListItem.previewPoolForTests, center: StaticLocationProvider.previewCoordinate)

        #expect(cards.count == 4)
        #expect(cards.map(\.id).contains("preview-cafe"))
        #expect(cards.filter(RecommendationPickerMode.attraction.matches).count == 2)
        #expect(cards.filter(RecommendationPickerMode.restaurant.matches).count == 2)
        #expect(cards.filter(RecommendationPickerMode.festival.matches).count == 0)
        #expect(cards.first?.distanceLabel.hasSuffix("km") == true)
    }

    @Test func pickerModesKeepMapLayerIdentity() {
        let response = RecommendationResponse.previewForTests
        let cards = RecommendationViewModel.normalize(response: response)

        #expect(cards.filter(RecommendationPickerMode.attraction.matches).map(\.id) == ["preview-seoul-park", "preview-gallery"])
        #expect(cards.filter(RecommendationPickerMode.restaurant.matches).map(\.id) == ["preview-market"])
        #expect(cards.filter(RecommendationPickerMode.festival.matches).isEmpty)
        #expect(RecommendationPickerMode.allCases.map(\.title) == ["장소", "식당", "축제"])
        #expect(RecommendationPickerMode.attraction.poolCopy == "장소 핀")
        #expect(RecommendationPickerMode.festival.poolCopy == "축제 핀")
    }

    @Test func placePoolNormalizerKeepsBackendCategorySeparateFromPickerBucket() throws {
        let shoppingPlace = PlaceListItem(
            id: "preview-shopping",
            name: "아이닥안경",
            category: "쇼핑",
            district: "서울 중구",
            address: "서울특별시 중구 명동",
            roadAddress: "서울특별시 중구 명동3길 6",
            summary: "서울 중구 권역의 쇼핑 후보입니다.",
            tags: ["쇼핑", "실내"],
            themeTags: ["서울", "가족나들이"],
            latitude: 37.5637,
            longitude: 126.9826,
            sourceAttribution: "한국관광공사 TourAPI",
            tourApi: nil
        )

        let card = try #require(RecommendationViewModel.normalize(places: [shoppingPlace], center: StaticLocationProvider.previewCoordinate).first)

        #expect(card.category == "쇼핑")
        #expect(RecommendationPickerMode(card: card).title == "장소")
        #expect(card.randomSlotKind == .attraction)
    }

    @Test func placePoolNormalizerClassifiesEventCategoriesAsFestival() throws {
        let eventPlace = PlaceListItem(
            id: "preview-event",
            name: "서울거리예술축제",
            category: "행사/공연/축제",
            district: "서울 중구",
            address: "서울특별시 중구",
            roadAddress: "서울특별시 중구 세종대로",
            summary: "서울 중구 권역의 축제 후보입니다.",
            tags: ["행사", "축제", "공연"],
            themeTags: ["서울", "축제행사"],
            latitude: 37.5665,
            longitude: 126.9780,
            sourceAttribution: "한국관광공사 TourAPI",
            tourApi: nil
        )

        let card = try #require(RecommendationViewModel.normalize(places: [eventPlace], center: StaticLocationProvider.previewCoordinate).first)

        #expect(card.subtitle == "축제 추천")
        #expect(card.category == "행사/공연/축제")
        #expect(card.randomSlotKind == .festival)
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

        #expect(provider.lastRequest?.themeId == nil)
        #expect(provider.lastRequest?.latitude == 35.1796)
        #expect(provider.lastRequest?.longitude == 129.0756)
        #expect(provider.recommendationCallCount == 1)
        #expect(provider.searchCallCount == 0)
        #expect(provider.lastRequest?.radiusKm == 3)
        #expect(viewModel.cards.count == 3)
    }

    @Test @MainActor func viewModelUsesPlacesEndpointAsMapPinPoolWhenAvailable() async {
        let provider = CapturingRecommendationProvider(placePool: PlaceListItem.previewPoolForTests)
        let locationProvider = StaticLocationProvider.preview
        let viewModel = RecommendationViewModel(provider: provider, locationProvider: locationProvider)

        await viewModel.loadGoNowRecommendations()

        #expect(provider.recommendationCallCount == 1)
        #expect(provider.placesCallCount == 1)
        #expect(viewModel.cards.count == 4)
        #expect(viewModel.cards.map(\.id).contains("preview-cafe"))
        #expect(viewModel.card(forSlotTitle: "식당 추천")?.randomSlotKind == .restaurant)
        #expect(viewModel.state == .results)
    }

    @Test @MainActor func viewModelRequestsLightweightNearbyPlacePoolForMapPins() async {
        let provider = CapturingRecommendationProvider(placePool: PlaceListItem.previewPoolForTests)
        let locationProvider = StaticLocationProvider(latitude: 35.1796, longitude: 129.0756)
        let viewModel = RecommendationViewModel(provider: provider, locationProvider: locationProvider)

        await viewModel.loadGoNowRecommendations()

        #expect(provider.lastPlacesQuery?.latitude == 35.1796)
        #expect(provider.lastPlacesQuery?.longitude == 129.0756)
        #expect(provider.lastPlacesQuery?.limit == 360)
        #expect(provider.lastPlacesQuery?.includeTourApi == false)
    }

    @Test @MainActor func viewModelDoesNotUsePreviewCardsAfterBackendFailure() async {
        let provider = CapturingRecommendationProvider()
        let locationProvider = StaticLocationProvider(latitude: 35.1796, longitude: 129.0756)
        let viewModel = RecommendationViewModel(provider: provider, locationProvider: locationProvider)

        await viewModel.loadGoNowRecommendations()
        let firstCardID = try! #require(viewModel.cards.first?.id)

        provider.shouldFailRecommendations = true
        await viewModel.loadGoNowRecommendations()

        #expect(viewModel.card(for: firstCardID)?.id == firstCardID)
        #expect(viewModel.cards.map(\.id) == ["preview-seoul-park", "preview-market", "preview-gallery"])
        #expect(viewModel.fallbackUsed == false)
        if case .error(let message) = viewModel.state {
            #expect(message.contains("백엔드에서 장소 후보를 불러오지 못했습니다."))
        } else {
            #expect(Bool(false), "Expected backend error state")
        }
    }

    @Test @MainActor func viewModelStartsAsSpontaneousRecommendationSurface() {
        let viewModel = RecommendationViewModel(
            provider: CapturingRecommendationProvider(),
            locationProvider: StaticLocationProvider.preview
        )

        #expect(viewModel.state == .ready)
        #expect(viewModel.cards.isEmpty)
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

    func with(title: String? = nil, subtitle: String? = nil, category: String? = nil) -> RecommendationCardModel {
        RecommendationCardModel(
            id: id,
            title: title ?? self.title,
            subtitle: subtitle ?? self.subtitle,
            reason: reason,
            category: category ?? self.category,
            district: district,
            roadAddress: roadAddress,
            latitude: latitude,
            longitude: longitude,
            distanceLabel: distanceLabel,
            sourceAttribution: sourceAttribution,
            tags: tags
        )
    }
}

private extension PlaceListItem {
    static let previewPoolForTests = [
        PlaceListItem(
            id: "preview-seoul-park",
            name: "서울 반려 산책 공원",
            category: "공원",
            district: "중구",
            address: "서울특별시 중구",
            roadAddress: "서울특별시 중구 세종대로",
            summary: "현재 위치 기준 산책 동선이 짧은 미리보기 장소입니다.",
            tags: ["산책", "반려동물"],
            themeTags: ["go-now"],
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
        ),
        PlaceListItem(
            id: "preview-cafe",
            name: "지도 옆 작은 카페",
            category: "카페",
            district: "중구",
            address: "서울특별시 중구",
            roadAddress: "서울특별시 중구 을지로",
            summary: "지도 후보 풀에 함께 뜨는 카페입니다.",
            tags: ["카페", "휴식"],
            themeTags: ["go-now"],
            latitude: 37.5681,
            longitude: 126.9771,
            sourceAttribution: "Preview",
            tourApi: nil
        )
    ]
}

private extension RecommendationResponse {
    static let previewForTests = RecommendationResponse(
        generatedAt: Date(timeIntervalSince1970: 0),
        source: SearchSourceMeta(providerId: "test", providerName: "test", status: "loaded", generatedAt: Date(timeIntervalSince1970: 0), count: places.count),
        fallbackUsed: true,
        randomScope: "테스트 랜덤",
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
        source: SearchSourceMeta(providerId: "test", providerName: "test", status: "loaded", generatedAt: Date(timeIntervalSince1970: 0), count: places.count),
        fallbackUsed: false,
        randomScope: "테스트 랜덤",
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
    private(set) var lastPlacesQuery: PlacesQuery?
    private(set) var recommendationCallCount = 0
    private(set) var placesCallCount = 0
    private(set) var searchCallCount = 0
    var shouldFailRecommendations = false
    var shouldFailPlaces = false
    private let response: RecommendationResponse
    private let placePool: [PlaceListItem]

    init(response: RecommendationResponse = .previewForTests, placePool: [PlaceListItem] = []) {
        self.response = response
        self.placePool = placePool
    }

    func health() async throws -> HealthResponse {
        HealthResponse(service: "test", status: "ok", time: Date(timeIntervalSince1970: 0))
    }

    func places() async throws -> PlacesResponse {
        placesCallCount += 1
        if shouldFailPlaces {
            throw URLError(.cannotLoadFromNetwork)
        }
        return PlacesResponse(source: SearchSourceMeta(providerId: "test", providerName: "test", status: "loaded", generatedAt: Date(timeIntervalSince1970: 0), count: placePool.count), total: placePool.count, places: placePool)
    }

    func places(query: PlacesQuery) async throws -> PlacesResponse {
        lastPlacesQuery = query
        return try await places()
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

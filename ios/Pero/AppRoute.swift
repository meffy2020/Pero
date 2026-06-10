import Foundation


struct RecommendationCardModel: Identifiable, Hashable {
    let id: String
    let title: String
    let subtitle: String
    let reason: String
    let category: String
    let district: String
    let roadAddress: String
    let latitude: Double
    let longitude: Double
    let distanceLabel: String
    let sourceAttribution: String
    let tags: [String]
    let eventPeriodLabel: String?
    let eventSummary: String?
    let officialURL: URL?
    let detail: PlaceDetailSnapshot?

    init(
        id: String,
        title: String,
        subtitle: String,
        reason: String,
        category: String,
        district: String,
        roadAddress: String,
        latitude: Double,
        longitude: Double,
        distanceLabel: String,
        sourceAttribution: String,
        tags: [String],
        eventPeriodLabel: String? = nil,
        eventSummary: String? = nil,
        officialURL: URL? = nil,
        detail: PlaceDetailSnapshot? = nil
    ) {
        self.id = id
        self.title = title
        self.subtitle = subtitle
        self.reason = reason
        self.category = category
        self.district = district
        self.roadAddress = roadAddress
        self.latitude = latitude
        self.longitude = longitude
        self.distanceLabel = distanceLabel
        self.sourceAttribution = sourceAttribution
        self.tags = tags
        self.eventPeriodLabel = eventPeriodLabel
        self.eventSummary = eventSummary
        self.officialURL = officialURL
        self.detail = detail
    }
}

struct PlaceDetailSnapshot: Hashable {
    let overview: String?
    let fields: [PlaceDetailField]
    let imageCount: Int

    init(
        overview: String? = nil,
        fields: [PlaceDetailField] = [],
        imageCount: Int = 0
    ) {
        self.overview = overview
        self.fields = fields
        self.imageCount = imageCount
    }
}

struct PlaceDetailField: Hashable, Identifiable {
    let id: String
    let icon: String
    let title: String
    let value: String

    init(icon: String, title: String, value: String) {
        self.id = "\(title)-\(value)"
        self.icon = icon
        self.title = title
        self.value = value
    }
}

extension RecommendationCardModel {
    var mapFirstSummaryChips: [String] {
        [distanceLabel, district, category]
    }

    var mapFirstAccessibilitySummary: String {
        "\(subtitle), \(title), \(distanceLabel), \(district), \(category)"
    }

    var mapPrimaryCTATitle: String {
        switch randomSlotKind {
        case .attraction:
            "이 범위에서 장소 뽑기"
        case .restaurant:
            "이 범위에서 식당 뽑기"
        case .festival:
            "이 범위에서 축제 뽑기"
        }
    }

    var randomSlotKind: RecommendationSlotKind {
        let primarySource = "\(subtitle) \(category)"
        let taggedSource = "\(primarySource) \(tags.joined(separator: " "))"
        let cafeDeniedSource = "\(taggedSource) \(title)"
        let containsCafeSignal = cafeDeniedSource.localizedCaseInsensitiveContains("카페")
            || cafeDeniedSource.localizedCaseInsensitiveContains("커피")
            || cafeDeniedSource.localizedCaseInsensitiveContains("디저트")
        let containsMealSignal = taggedSource.contains("식사")
            || taggedSource.contains("식당")
            || taggedSource.contains("음식점")
            || taggedSource.contains("한식")
            || taggedSource.contains("중식")
            || taggedSource.contains("일식")
            || taggedSource.contains("양식")
            || taggedSource.contains("분식")
            || taggedSource.contains("육류")
            || taggedSource.contains("고기")
            || taggedSource.contains("곱창")
            || taggedSource.contains("막창")
            || taggedSource.contains("치킨")
            || taggedSource.contains("국밥")
            || taggedSource.contains("찌개")
            || taggedSource.contains("국수")
            || taggedSource.contains("구내식")
            || taggedSource.contains("구내식당")
            || taggedSource.contains("한정식")
            || taggedSource.localizedCaseInsensitiveContains("meal")
            || taggedSource.localizedCaseInsensitiveContains("restaurant")
        if sourceAttribution == "kakaoLocal", containsMealSignal, !containsCafeSignal {
            return .restaurant
        }
        if taggedSource.contains("축제")
            || taggedSource.contains("행사")
            || taggedSource.contains("공연")
            || taggedSource.localizedCaseInsensitiveContains("festival") {
            return .festival
        }
        if containsMealSignal, !containsCafeSignal {
            return .restaurant
        }
        return .attraction
    }

    var categoryIconName: String {
        switch category {
        case let value where value.contains("음식") || value.contains("식당") || value.contains("레스토랑"):
            "fork.knife.circle.fill"
        case let value where value.contains("행사") || value.contains("축제") || value.contains("공연"):
            "sparkles"
        case let value where value.contains("쇼핑"):
            "bag.circle.fill"
        case let value where value.contains("숙박"):
            "bed.double.circle.fill"
        case let value where value.contains("레포츠") || value.contains("스포츠"):
            "figure.run.circle.fill"
        case let value where value.contains("전시") || value.contains("문화"):
            "building.columns.circle.fill"
        default:
            "leaf.circle.fill"
        }
    }

    var mapMarkerKind: KakaoMapMarker.Kind {
        let source = "\(subtitle) \(category) \(tags.joined(separator: " "))"
        if source.contains("행사") || source.contains("축제") || source.contains("공연") {
            return .festival
        }
        if source.contains("음식") || source.contains("식당") || source.contains("레스토랑") {
            return .restaurant
        }
        if source.contains("쇼핑") || source.contains("시장") {
            return .shopping
        }
        if source.contains("숙박") || source.contains("호텔") {
            return .lodging
        }
        if source.contains("레포츠") || source.contains("스포츠") || source.contains("체험") {
            return .activity
        }
        if source.contains("전시") || source.contains("문화") || source.contains("박물관") || source.contains("미술") {
            return .culture
        }
        return .attraction
    }

    var kakaoMapDirectionsAppURL: URL? {
        var components = URLComponents()
        components.scheme = "kakaomap"
        components.host = "route"
        components.queryItems = [
            URLQueryItem(name: "ep", value: mapCoordinateQueryValue),
            URLQueryItem(name: "by", value: "foot")
        ]
        return components.url
    }

    var kakaoMapDirectionsWebURL: URL {
        let destination = "\(title),\(latitude),\(longitude)"
            .addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? "\(latitude),\(longitude)"
        return URL(string: "https://map.kakao.com/link/to/\(destination)")!
    }

    var kakaoMapDirectionsMobileWebURL: URL {
        var components = URLComponents()
        components.scheme = "https"
        components.host = "m.map.kakao.com"
        components.path = "/scheme/route"
        components.queryItems = [
            URLQueryItem(name: "ep", value: mapCoordinateQueryValue),
            URLQueryItem(name: "by", value: "foot")
        ]
        return components.url ?? kakaoMapDirectionsWebURL
    }

    private var mapCoordinateQueryValue: String {
        "\(latitude),\(longitude)"
    }
}

enum RecommendationSlotKind: Hashable {
    case attraction
    case restaurant
    case festival
}

enum RecommendationPickerMode: String, CaseIterable, Hashable, Identifiable {
    case attraction
    case restaurant
    case festival

    var id: String { rawValue }

    init(card: RecommendationCardModel) {
        switch card.randomSlotKind {
        case .attraction:
            self = .attraction
        case .restaurant:
            self = .restaurant
        case .festival:
            self = .festival
        }
    }

    var title: String {
        switch self {
        case .attraction: "장소"
        case .restaurant: "식당"
        case .festival: "축제"
        }
    }

    var shortTitle: String {
        switch self {
        case .attraction: "장소"
        case .restaurant: "식당"
        case .festival: "축제"
        }
    }

    var symbolName: String {
        switch self {
        case .attraction: "mappin.and.ellipse"
        case .restaurant: "fork.knife.circle.fill"
        case .festival: "sparkles"
        }
    }

    var poolCopy: String {
        switch self {
        case .attraction: "장소 핀"
        case .restaurant: "식당 핀"
        case .festival: "축제 핀"
        }
    }

    var apiMode: String {
        switch self {
        case .attraction: "tour"
        case .restaurant: "restaurant"
        case .festival: "festival"
        }
    }

    var apiCategory: String? {
        switch self {
        case .attraction: nil
        case .restaurant: nil
        case .festival: "행사/공연/축제"
        }
    }

    var apiSource: String? {
        switch self {
        case .restaurant: "kakaoLocal"
        default: nil
        }
    }

    var apiActiveFestival: Bool? {
        nil
    }

    func matches(_ card: RecommendationCardModel) -> Bool {
        RecommendationPickerMode(card: card) == self
    }
}

enum AppRoute: Hashable {
    case recommendationDetail(cardID: RecommendationCardModel.ID)
    case mapFocus(cardID: RecommendationCardModel.ID)

    var cardID: RecommendationCardModel.ID {
        switch self {
        case .recommendationDetail(let cardID), .mapFocus(let cardID):
            cardID
        }
    }
}

enum RecommendationState: Equatable {
    case ready
    case loading
    case results
    case empty
    case error(String)

    var title: String {
        switch self {
        case .ready: "지도 준비"
        case .loading: ""
        case .results: "추천 결과"
        case .empty: ""
        case .error: "연결 확인 필요"
        }
    }
}

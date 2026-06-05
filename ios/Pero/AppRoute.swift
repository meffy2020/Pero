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
        eventSummary: String? = nil
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
            "지도에서 관광지 뽑기"
        case .restaurant:
            "지도에서 식당 뽑기"
        case .festival:
            "지도에서 축제 뽑기"
        }
    }

    var randomSlotKind: RecommendationSlotKind {
        let primarySource = "\(subtitle) \(category)"
        let taggedSource = "\(primarySource) \(tags.joined(separator: " "))"
        if taggedSource.contains("축제")
            || taggedSource.contains("행사")
            || taggedSource.contains("공연")
            || taggedSource.localizedCaseInsensitiveContains("festival") {
            return .festival
        }
        if primarySource.contains("식사")
            || primarySource.contains("식당")
            || primarySource.contains("음식점")
            || primarySource.contains("카페")
            || primarySource.localizedCaseInsensitiveContains("meal")
            || primarySource.localizedCaseInsensitiveContains("restaurant") {
            return .restaurant
        }
        return .attraction
    }

    var categoryIconName: String {
        switch category {
        case let value where value.contains("음식") || value.contains("식당"):
            "fork.knife.circle.fill"
        case let value where value.contains("전시") || value.contains("문화"):
            "building.columns.circle.fill"
        default:
            "leaf.circle.fill"
        }
    }

    var appleMapsURL: URL? {
        var components = URLComponents()
        components.scheme = "http"
        components.host = "maps.apple.com"
        components.queryItems = [
            URLQueryItem(name: "ll", value: mapCoordinateQueryValue),
            URLQueryItem(name: "q", value: title)
        ]
        return components.url
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
        case .attraction: "관광지"
        case .restaurant: "식당"
        case .festival: "축제"
        }
    }

    var shortTitle: String {
        switch self {
        case .attraction: "관광지"
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
        case .attraction: "관광지 핀"
        case .restaurant: "식당 핀"
        case .festival: "축제 핀"
        }
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
        case .loading: "지금 갈 곳 찾는 중"
        case .results: "추천 결과"
        case .empty: "추천 후보 없음"
        case .error: "연결 확인 필요"
        }
    }
}

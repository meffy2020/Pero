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
        case .place:
            "지도에서 랜덤 장소 보기"
        case .restaurant:
            "지도에서 식당 위치 보기"
        case .course:
            "지도에서 코스 시작점 보기"
        }
    }

    var randomSlotKind: RecommendationSlotKind {
        let source = "\(subtitle) \(category) \(title)"
        if source.contains("코스") || source.contains("차") || source.localizedCaseInsensitiveContains("course") {
            return .course
        }
        if source.contains("식사")
            || source.contains("식당")
            || source.contains("음식")
            || source.contains("카페")
            || source.localizedCaseInsensitiveContains("meal") {
            return .restaurant
        }
        return .place
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
    case place
    case restaurant
    case course
}

enum RecommendationPickerMode: String, CaseIterable, Hashable, Identifiable {
    case place
    case restaurant
    case course

    var id: String { rawValue }

    init(card: RecommendationCardModel) {
        switch card.randomSlotKind {
        case .place:
            self = .place
        case .restaurant:
            self = .restaurant
        case .course:
            self = .course
        }
    }

    var title: String {
        switch self {
        case .place: "장소"
        case .restaurant: "식당"
        case .course: "코스"
        }
    }

    var shortTitle: String {
        switch self {
        case .place: "장소"
        case .restaurant: "식당"
        case .course: "코스"
        }
    }

    var symbolName: String {
        switch self {
        case .place: "sparkles.square.filled.on.square"
        case .restaurant: "fork.knife.circle.fill"
        case .course: "point.topleft.down.curvedto.point.bottomright.up.fill"
        }
    }

    var poolCopy: String {
        switch self {
        case .place: "주변 장소 핀"
        case .restaurant: "식사 후보 핀"
        case .course: "코스 시작점"
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

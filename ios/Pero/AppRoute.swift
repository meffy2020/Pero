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
            URLQueryItem(name: "ll", value: "\(latitude),\(longitude)"),
            URLQueryItem(name: "q", value: title)
        ]
        return components.url
    }
}

enum RecommendationSlotKind: Hashable {
    case place
    case restaurant
    case course
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
        case .ready: "현재 위치 준비"
        case .loading: "지금 갈 곳 찾는 중"
        case .results: "추천 결과"
        case .empty: "추천 후보 없음"
        case .error: "연결 확인 필요"
        }
    }
}

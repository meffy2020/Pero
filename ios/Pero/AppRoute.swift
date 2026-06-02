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

enum AppRoute: Hashable {
    case recommendationDetail(RecommendationCardModel)
    case mapFocus(RecommendationCardModel)
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

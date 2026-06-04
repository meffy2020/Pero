import SwiftUI
import CoreLocation
import PeroCore

struct ContentView: View {
    @StateObject private var viewModel: RecommendationViewModel
    @State private var path: [AppRoute] = []

    init(
        provider: PeroAPIProviding,
        locationProvider: LocationProviding
    ) {
        _viewModel = StateObject(wrappedValue: RecommendationViewModel(provider: provider, locationProvider: locationProvider))
    }

    var body: some View {
        NavigationStack(path: $path) {
            HomeRecommendationScreen(viewModel: viewModel)
                .navigationDestination(for: AppRoute.self, destination: routeView)
        }
        .task {
            await viewModel.loadGoNowRecommendations()
        }
    }

    @ViewBuilder
    private func routeView(for route: AppRoute) -> some View {
        if let selectedCard = viewModel.card(for: route.cardID) {
            switch route {
            case .recommendationDetail:
                PlaceExplanationDetailScreen(card: selectedCard)
            case .mapFocus:
                MapScreen(card: selectedCard)
            }
        } else {
            StateMessageView(
                icon: "exclamationmark.triangle",
                title: "추천 정보를 다시 불러와 주세요",
                message: "선택한 추천 카드가 현재 목록에서 사라졌습니다."
            )
            .padding()
        }
    }
}

struct UserCoordinate: Equatable {
    let latitude: Double
    let longitude: Double

    var displayLabel: String {
        "내 주변"
    }
}

protocol LocationProviding: AnyObject, Sendable {
    func currentCoordinate() async throws -> UserCoordinate
}

enum LocationProviderError: LocalizedError {
    case permissionDenied
    case unavailable

    var errorDescription: String? {
        switch self {
        case .permissionDenied:
            return "위치 권한이 필요합니다."
        case .unavailable:
            return "현재 위치를 확인할 수 없습니다."
        }
    }
}

final class CoreLocationProvider: LocationProviding, @unchecked Sendable {
    func currentCoordinate() async throws -> UserCoordinate {
        for try await update in CLLocationUpdate.liveUpdates() {
            if update.authorizationDenied {
                throw LocationProviderError.permissionDenied
            }
            if let location = update.location {
                return UserCoordinate(latitude: location.coordinate.latitude, longitude: location.coordinate.longitude)
            }
        }
        throw LocationProviderError.unavailable
    }
}

final class StaticLocationProvider: LocationProviding, @unchecked Sendable {
    static let previewCoordinate = UserCoordinate(latitude: 37.5665, longitude: 126.9780)
    static let preview = StaticLocationProvider(latitude: previewCoordinate.latitude, longitude: previewCoordinate.longitude)

    private let coordinate: UserCoordinate

    init(latitude: Double, longitude: Double) {
        self.coordinate = UserCoordinate(latitude: latitude, longitude: longitude)
    }

    func currentCoordinate() async throws -> UserCoordinate {
        coordinate
    }
}

@MainActor
final class RecommendationViewModel: ObservableObject {
    @Published private(set) var state: RecommendationState = .ready
    @Published private(set) var cards: [RecommendationCardModel] = []
    @Published private(set) var fallbackUsed = false

    @Published private(set) var locationLabel = "현재 위치 확인 전"
    private var cardsByID: [RecommendationCardModel.ID: RecommendationCardModel] = [:]

    private let provider: PeroAPIProviding
    private let locationProvider: LocationProviding

    init(provider: PeroAPIProviding, locationProvider: LocationProviding) {
        self.provider = provider
        self.locationProvider = locationProvider
    }

    func loadGoNowRecommendations() async {
        state = .loading
        fallbackUsed = false
        do {
            let coordinate = try await locationProvider.currentCoordinate()
            locationLabel = coordinate.displayLabel
            let request = RecommendationRequest(
                themeId: "go-now",
                latitude: coordinate.latitude,
                longitude: coordinate.longitude,
                radiusKm: 3
            )
            let recommendationResponse = try? await provider.recommendations(request)
            let placesResponse = try? await provider.places()
            let placePool = Self.normalize(places: placesResponse?.places ?? [], center: coordinate)

            if !placePool.isEmpty {
                apply(cards: placePool, fallback: recommendationResponse?.fallbackUsed ?? false)
            } else if let recommendationResponse {
                apply(response: recommendationResponse)
            } else {
                throw LocationProviderError.unavailable
            }
        } catch {
            do {
                let previewProvider = PeroAPIProviderFactory.preview()
                let previewCoordinate = StaticLocationProvider.previewCoordinate
                let places = (try await previewProvider.places()).places
                let previewPool = Self.normalize(places: places, center: previewCoordinate)
                if !previewPool.isEmpty {
                    locationLabel = "미리보기 추천 영역"
                    apply(cards: previewPool, fallback: true)
                } else {
                    let response = try await previewProvider.recommendations(
                        RecommendationRequest(themeId: "go-now", radiusKm: 3)
                    )
                    locationLabel = "미리보기 추천 영역"
                    apply(response: response, forceFallback: true)
                }
            } catch {
                fallbackUsed = false
                locationLabel = "위치 또는 추천 서버 확인 필요"
                state = .error("현재 위치 기반 추천을 불러오지 못했습니다. \(error.localizedDescription)")
            }
        }
    }

    func card(for id: RecommendationCardModel.ID) -> RecommendationCardModel? {
        cards.first { $0.id == id } ?? cardsByID[id]
    }

    func card(forSlotTitle slotTitle: String) -> RecommendationCardModel? {
        cards.first { $0.subtitle == slotTitle }
    }

    private func apply(response: RecommendationResponse, forceFallback: Bool = false) {
        apply(cards: Self.normalize(response: response), fallback: forceFallback || response.fallbackUsed)
    }

    private func apply(cards normalizedCards: [RecommendationCardModel], fallback: Bool = false) {
        fallbackUsed = fallback
        cards = normalizedCards
        cache(cards: normalizedCards)
        state = normalizedCards.isEmpty ? .empty : .results
    }

    private func cache(cards: [RecommendationCardModel]) {
        for card in cards {
            cardsByID[card.id] = card
        }
    }

    nonisolated static func normalize(response: RecommendationResponse) -> [RecommendationCardModel] {
        var normalized: [RecommendationCardModel] = []
        var seenIDs: Set<String> = []

        append(card: response.nearbyPick, slotTitle: "랜덤 장소 추천", into: &normalized, seenIDs: &seenIDs)
        append(card: response.mealPick, slotTitle: "식당 추천", into: &normalized, seenIDs: &seenIDs)
        response.dateCourse?.stops.forEach { stop in
            guard normalized.count < 3 else { return }
            append(place: stop.place, title: "랜덤 코스 추천", description: response.dateCourse?.description, into: &normalized, seenIDs: &seenIDs)
        }

        return Array(normalized.prefix(3))
    }
    nonisolated static func normalize(places: [PlaceListItem], center: UserCoordinate) -> [RecommendationCardModel] {
        places.compactMap { place in
            guard place.latitude.isFinite, place.longitude.isFinite else { return nil }
            let distanceKm = center.distanceKm(toLatitude: place.latitude, longitude: place.longitude)
            return RecommendationCardModel(
                id: place.id,
                title: place.name,
                subtitle: Self.slotTitle(for: place),
                reason: place.summary.isEmpty ? "현재 지도 후보 풀에 포함된 장소입니다." : place.summary,
                category: place.category,
                district: place.district,
                roadAddress: place.roadAddress,
                latitude: place.latitude,
                longitude: place.longitude,
                distanceLabel: String(format: "%.1fkm", distanceKm),
                sourceAttribution: place.sourceAttribution,
                tags: Array((place.tags + place.themeTags).uniqued().prefix(4))
            )
        }
        .sorted { lhs, rhs in
            lhs.distanceValueForSorting < rhs.distanceValueForSorting
        }
    }


    nonisolated private static func slotTitle(for place: PlaceListItem) -> String {
        let source = "\(place.category) \(place.name) \(place.tags.joined(separator: " ")) \(place.themeTags.joined(separator: " "))"
        if source.contains("식사") || source.contains("식당") || source.contains("음식") || source.contains("카페") {
            return "식당 추천"
        }
        if source.contains("코스") || source.contains("전시") || source.contains("문화") || source.contains("관광") || source.contains("체험") {
            return "랜덤 코스 추천"
        }
        return "랜덤 장소 추천"
    }

    nonisolated private static func append(card: RecommendationCard?, slotTitle: String, into normalized: inout [RecommendationCardModel], seenIDs: inout Set<String>) {
        guard normalized.count < 3, let card else { return }
        append(place: card.place, title: slotTitle, description: card.description, into: &normalized, seenIDs: &seenIDs)
    }

    nonisolated private static func append(place: RecommendationPlace?, title: String, description: String?, into normalized: inout [RecommendationCardModel], seenIDs: inout Set<String>) {
        guard let place, place.latitude.isFinite, place.longitude.isFinite, seenIDs.insert(place.id).inserted else { return }
        let reason = if let description, !description.isEmpty {
            "\(description) \(place.reason)"
        } else {
            place.reason
        }
        normalized.append(
            RecommendationCardModel(
                id: place.id,
                title: place.name,
                subtitle: title,
                reason: reason,
                category: place.category,
                district: place.district,
                roadAddress: place.roadAddress,
                latitude: place.latitude,
                longitude: place.longitude,
                distanceLabel: place.distanceKm.map { String(format: "%.1fkm", $0) } ?? "거리 정보 없음",
                sourceAttribution: place.sourceAttribution,
                tags: Array(place.tags.prefix(4))
            )
        )
    }
}

private extension UserCoordinate {
    func distanceKm(toLatitude latitude: Double, longitude: Double) -> Double {
        let earthRadiusKm = 6371.0
        let lat1 = self.latitude * .pi / 180
        let lat2 = latitude * .pi / 180
        let deltaLat = (latitude - self.latitude) * .pi / 180
        let deltaLon = (longitude - self.longitude) * .pi / 180
        let a = sin(deltaLat / 2) * sin(deltaLat / 2)
            + cos(lat1) * cos(lat2) * sin(deltaLon / 2) * sin(deltaLon / 2)
        return earthRadiusKm * 2 * atan2(sqrt(a), sqrt(1 - a))
    }
}

private extension RecommendationCardModel {
    var distanceValueForSorting: Double {
        Double(distanceLabel.replacingOccurrences(of: "km", with: "")) ?? .greatestFiniteMagnitude
    }
}

private extension Array where Element: Hashable {
    func uniqued() -> [Element] {
        var seen: Set<Element> = []
        return filter { seen.insert($0).inserted }
    }
}

#Preview {
    ContentView(provider: PeroAPIProviderFactory.preview(), locationProvider: StaticLocationProvider.preview)
}

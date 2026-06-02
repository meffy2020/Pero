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
                .navigationTitle("Pero")
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
        String(format: "현재 위치 %.4f, %.4f", latitude, longitude)
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
    static let preview = StaticLocationProvider(latitude: 37.5665, longitude: 126.9780)

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
            let response = try await provider.recommendations(
                RecommendationRequest(
                    themeId: "go-now",
                    latitude: coordinate.latitude,
                    longitude: coordinate.longitude,
                    radiusKm: 3
                )
            )
            fallbackUsed = response.fallbackUsed
            cards = Self.normalize(response: response)
            state = cards.isEmpty ? .empty : .results
        } catch {
            cards = []
            fallbackUsed = false
            locationLabel = "위치 또는 추천 서버 확인 필요"
            state = .error("현재 위치 기반 추천을 불러오지 못했습니다. \(error.localizedDescription)")
        }
    }

    func card(for id: RecommendationCardModel.ID) -> RecommendationCardModel? {
        cards.first { $0.id == id }
    }

    nonisolated static func normalize(response: RecommendationResponse) -> [RecommendationCardModel] {
        var normalized: [RecommendationCardModel] = []
        var seenIDs: Set<String> = []

        append(card: response.nearbyPick, into: &normalized, seenIDs: &seenIDs)
        append(card: response.mealPick, into: &normalized, seenIDs: &seenIDs)
        response.dateCourse?.stops.forEach { stop in
            guard normalized.count < 3 else { return }
            append(place: stop.place, title: stop.slot, description: response.dateCourse?.description, into: &normalized, seenIDs: &seenIDs)
        }

        return Array(normalized.prefix(3))
    }

    nonisolated private static func append(card: RecommendationCard?, into normalized: inout [RecommendationCardModel], seenIDs: inout Set<String>) {
        guard normalized.count < 3, let card else { return }
        append(place: card.place, title: card.title, description: card.description, into: &normalized, seenIDs: &seenIDs)
    }

    nonisolated private static func append(place: RecommendationPlace?, title: String, description: String?, into normalized: inout [RecommendationCardModel], seenIDs: inout Set<String>) {
        guard let place, place.latitude.isFinite, place.longitude.isFinite, seenIDs.insert(place.id).inserted else { return }
        normalized.append(
            RecommendationCardModel(
                id: place.id,
                title: place.name,
                subtitle: title,
                reason: description?.isEmpty == false ? "\(description!) \(place.reason)" : place.reason,
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

#Preview {
    ContentView(provider: PeroAPIProviderFactory.preview(), locationProvider: StaticLocationProvider.preview)
}

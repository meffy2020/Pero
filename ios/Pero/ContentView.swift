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

final class CoreLocationProvider: NSObject, LocationProviding, CLLocationManagerDelegate, @unchecked Sendable {
    private let manager = CLLocationManager()
    private var pendingContinuation: CheckedContinuation<UserCoordinate, Error>?

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
    }

    func currentCoordinate() async throws -> UserCoordinate {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.main.async { [weak self] in
                self?.requestCurrentCoordinate(continuation: continuation)
            }
        }
    }

    private func requestCurrentCoordinate(continuation: CheckedContinuation<UserCoordinate, Error>) {
        guard pendingContinuation == nil else {
            continuation.resume(throwing: LocationProviderError.unavailable)
            return
        }

        switch manager.authorizationStatus {
        case .notDetermined:
            pendingContinuation = continuation
            manager.requestWhenInUseAuthorization()
        case .authorizedAlways, .authorizedWhenInUse:
            pendingContinuation = continuation
            if let location = manager.location, abs(location.timestamp.timeIntervalSinceNow) < 30 {
                resume(with: location)
            } else {
                manager.requestLocation()
            }
        case .denied, .restricted:
            continuation.resume(throwing: LocationProviderError.permissionDenied)
        @unknown default:
            continuation.resume(throwing: LocationProviderError.unavailable)
        }
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        guard pendingContinuation != nil else { return }
        switch manager.authorizationStatus {
        case .authorizedAlways, .authorizedWhenInUse:
            manager.requestLocation()
        case .denied, .restricted:
            resume(throwing: LocationProviderError.permissionDenied)
        case .notDetermined:
            break
        @unknown default:
            resume(throwing: LocationProviderError.unavailable)
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else {
            resume(throwing: LocationProviderError.unavailable)
            return
        }
        resume(with: location)
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        resume(throwing: error)
    }

    private func resume(with location: CLLocation) {
        let coordinate = UserCoordinate(latitude: location.coordinate.latitude, longitude: location.coordinate.longitude)
        pendingContinuation?.resume(returning: coordinate)
        pendingContinuation = nil
    }

    private func resume(throwing error: Error) {
        pendingContinuation?.resume(throwing: error)
        pendingContinuation = nil
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

    private var cardsByID: [RecommendationCardModel.ID: RecommendationCardModel] = [:]

    private let provider: PeroAPIProviding
    private let locationProvider: LocationProviding

    init(provider: PeroAPIProviding, locationProvider: LocationProviding) {
        self.provider = provider
        self.locationProvider = locationProvider
    }

    func currentCoordinate() async throws -> UserCoordinate {
        try await locationProvider.currentCoordinate()
    }

    func loadGoNowRecommendations() async {
        do {
            let coordinate = try await locationProvider.currentCoordinate()
            await loadGoNowRecommendations(center: coordinate)
        } catch {
            do {
                try await loadLiveRecommendations(center: StaticLocationProvider.previewCoordinate, forceFallback: true)
            } catch {
                fallbackUsed = false
                state = .error("백엔드에서 장소 후보를 불러오지 못했습니다. \(error.localizedDescription)")
            }
        }
    }

    func loadGoNowRecommendations(center coordinate: UserCoordinate) async {
        state = .loading
        fallbackUsed = false
        do {
            try await loadLiveRecommendations(center: coordinate)
        } catch {
            fallbackUsed = false
            state = .error("백엔드에서 장소 후보를 불러오지 못했습니다. \(error.localizedDescription)")
        }
    }

    private func loadLiveRecommendations(center coordinate: UserCoordinate, forceFallback: Bool = false) async throws {
        let request = RecommendationRequest(
            themeId: nil,
            latitude: coordinate.latitude,
            longitude: coordinate.longitude,
            radiusKm: 3
        )
        let recommendationResponse = try? await provider.recommendations(request)
        let placesResponse = try await provider.places()
        let placePool = Self.normalize(places: placesResponse.places, center: coordinate)

        if !placePool.isEmpty {
            apply(cards: placePool, fallback: forceFallback || (recommendationResponse?.fallbackUsed ?? false))
        } else if let recommendationResponse {
            apply(response: recommendationResponse, forceFallback: forceFallback)
        } else {
            throw LocationProviderError.unavailable
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
                tags: Array((place.tags + place.themeTags).uniqued().prefix(4)),
                eventPeriodLabel: Self.eventPeriodLabel(from: place.tourApi),
                eventSummary: Self.eventSummary(summary: place.summary, tourApi: place.tourApi)
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

    nonisolated private static func eventPeriodLabel(from tourApi: TourAPI?) -> String? {
        guard let common = tourApi?.common else { return nil }
        let start = formattedEventDate(common.eventStartDate)
        let end = formattedEventDate(common.eventEndDate)
        switch (start, end) {
        case let (start?, end?) where start == end:
            return start
        case let (start?, end?):
            return "\(start) - \(end)"
        case let (start?, nil):
            return start
        case let (nil, end?):
            return "~ \(end)"
        default:
            return nil
        }
    }

    nonisolated private static func formattedEventDate(_ rawValue: String?) -> String? {
        guard let rawValue else { return nil }
        let digits = rawValue.filter(\.isNumber)
        guard digits.count == 8 else { return rawValue.isEmpty ? nil : rawValue }
        let year = digits.prefix(4)
        let monthStart = digits.index(digits.startIndex, offsetBy: 4)
        let dayStart = digits.index(digits.startIndex, offsetBy: 6)
        let month = digits[monthStart..<dayStart]
        let day = digits[dayStart..<digits.endIndex]
        return "\(year).\(month).\(day)"
    }

    nonisolated private static func eventSummary(summary: String, tourApi: TourAPI?) -> String? {
        let source = tourApi?.common?.overview?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
            ? tourApi?.common?.overview
            : summary
        guard let source else { return nil }
        let flattened = source
            .replacingOccurrences(of: "<br>", with: " ")
            .replacingOccurrences(of: "<br/>", with: " ")
            .replacingOccurrences(of: "<br />", with: " ")
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !flattened.isEmpty else { return nil }
        if flattened.count <= 96 { return flattened }
        let endIndex = flattened.index(flattened.startIndex, offsetBy: 96)
        return String(flattened[..<endIndex]) + "…"
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
                tags: Array(place.tags.prefix(4)),
                eventPeriodLabel: Self.eventPeriodLabel(from: place.tourApi),
                eventSummary: Self.eventSummary(summary: place.summary, tourApi: place.tourApi)
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

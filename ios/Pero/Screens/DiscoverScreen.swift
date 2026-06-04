import SwiftUI
import MapKit
import PeroCore

struct HomeRecommendationScreen: View {
    @ObservedObject var viewModel: RecommendationViewModel
    @State private var pickerMode: RecommendationPickerMode = .place
    @State private var selectedCardID: RecommendationCardModel.ID?
    @State private var rerollTask: Task<Void, Never>?
    @State private var cameraPosition: MapCameraPosition = .region(Self.defaultRegion)

    private static let defaultRegion = MKCoordinateRegion(
        center: CLLocationCoordinate2D(latitude: 37.5665, longitude: 126.9780),
        span: MKCoordinateSpan(latitudeDelta: 0.055, longitudeDelta: 0.055)
    )

    private var candidateCards: [RecommendationCardModel] {
        viewModel.cards.filter { pickerMode.matches($0) }
    }

    private var visiblePoolCount: Int {
        candidateCards.count
    }

    private var selectedCard: RecommendationCardModel? {
        if let selectedCardID, let card = viewModel.card(for: selectedCardID), pickerMode.matches(card) {
            return card
        }
        return candidateCards.first ?? viewModel.cards.first
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            mapCanvas
            mapOverlay
        }
        .ignoresSafeArea(.container, edges: .bottom)
        .refreshable {
            await viewModel.loadGoNowRecommendations()
        }
        .onChange(of: viewModel.cards) { _, cards in
            reconcileSelection(with: cards)
        }
        .onChange(of: pickerMode) { _, _ in
            reconcileSelection(with: viewModel.cards)
        }
        .onDisappear {
            rerollTask?.cancel()
        }
    }

    private var mapCanvas: some View {
        Map(position: $cameraPosition) {
            ForEach(viewModel.cards) { card in
                Annotation(card.title, coordinate: card.coordinate) {
                    Button {
                        select(card)
                    } label: {
                        VStack(spacing: 4) {
                            Image(systemName: markerSymbol(for: card))
                                .font(.system(size: selectedCard?.id == card.id ? 28 : 22, weight: .semibold))
                                .foregroundStyle(selectedCard?.id == card.id ? Color.blue : Color.secondary)
                                .background(.regularMaterial, in: Circle())
                            if selectedCard?.id == card.id {
                                Text(card.title)
                                    .font(.caption2)
                                    .foregroundStyle(.primary)
                                    .lineLimit(1)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .nativePanel(cornerRadius: 10)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("\(card.title) 선택")
                }
            }
        }
        .mapStyle(.standard(elevation: .realistic, pointsOfInterest: .including([.park, .restaurant, .museum])))
    }

    private var mapOverlay: some View {
        VStack(spacing: 0) {
            headerPanel
            Spacer(minLength: 0)
            currentAreaPill
            randomPickButton
            selectedResultSheet
        }
        .padding(.horizontal, 16)
        .safeAreaPadding(.top, 12)
        .safeAreaPadding(.bottom, 14)
    }

    private var headerPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("지금 뭐 하지?")
                        .font(.title.weight(.bold))
                    Text("현재 지도 안 후보에서 하나를 고릅니다")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 8)
                Label(viewModel.locationLabel, systemImage: "location.fill")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .multilineTextAlignment(.trailing)
            }

            Picker("추천 종류", selection: $pickerMode) {
                ForEach(RecommendationPickerMode.allCases) { mode in
                    Text(mode.title).tag(mode)
                }
            }
            .pickerStyle(.segmented)
        }
        .padding(16)
        .nativePanel(cornerRadius: 20)
    }

    private var currentAreaPill: some View {
        Label("후보 \(visiblePoolCount)개 · \(pickerMode.poolCopy)" + (viewModel.fallbackUsed ? " · 반경 보완" : ""), systemImage: "scope")
            .font(.footnote.weight(.semibold))
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .nativePanel(cornerRadius: 14)
            .padding(.bottom, 8)
    }

    private var randomPickButton: some View {
        Button {
            pickRandomCandidate()
        } label: {
            Label(randomButtonTitle, systemImage: viewModel.state == .loading ? "hourglass" : "shuffle")
                .font(.headline)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 4)
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
        .tint(.blue)
        .disabled(viewModel.state == .loading || candidateCards.isEmpty)
        .padding(.bottom, 10)
        .accessibilityIdentifier("mapRandomPickButton")
    }

    private var randomButtonTitle: String {
        switch viewModel.state {
        case .loading:
            "후보 스캔 중"
        default:
            "\(pickerMode.shortTitle) 랜덤 선택"
        }
    }

    @ViewBuilder
    private var selectedResultSheet: some View {
        if let selectedCard {
            RandomMapResultSheet(
                card: selectedCard,
                mode: pickerMode,
                visiblePoolCount: visiblePoolCount,
                reroll: pickRandomCandidate
            )
            .transition(.move(edge: .bottom).combined(with: .opacity))
        } else {
            StateMessageView(
                icon: stateIcon,
                title: viewModel.state.title,
                message: stateMessage
            )
            .nativePanel(cornerRadius: 20)
        }
    }

    private func rerollRecommendations() {
        rerollTask?.cancel()
        rerollTask = Task {
            await viewModel.loadGoNowRecommendations()
        }
    }

    private func pickRandomCandidate() {
        if let random = candidateCards.randomElement() {
            select(random)
            return
        }
        rerollRecommendations()
    }

    private func select(_ card: RecommendationCardModel) {
        selectedCardID = card.id
        cameraPosition = .region(
            MKCoordinateRegion(
                center: card.coordinate,
                span: MKCoordinateSpan(latitudeDelta: 0.018, longitudeDelta: 0.018)
            )
        )
    }

    private func reconcileSelection(with cards: [RecommendationCardModel]) {
        if let selectedCardID,
           cards.contains(where: { $0.id == selectedCardID && pickerMode.matches($0) }) {
            return
        }
        if let first = cards.first(where: pickerMode.matches) ?? cards.first {
            select(first)
        } else {
            selectedCardID = nil
        }
    }

    private func markerSymbol(for card: RecommendationCardModel) -> String {
        RecommendationPickerMode(card: card).symbolName
    }

    private var stateIcon: String {
        switch viewModel.state {
        case .ready: "location"
        case .loading: "scope"
        case .results: "sparkles"
        case .empty: "tray"
        case .error: "exclamationmark.triangle"
        }
    }

    private var stateMessage: String {
        switch viewModel.state {
        case .ready:
            HomeMapKoreanCopy.readyMessage
        case .loading:
            HomeMapKoreanCopy.loadingMessage
        case .results:
            "지도 안 후보를 선택해 결과를 확인하세요."
        case .empty:
            HomeMapKoreanCopy.emptyMessage
        case .error(let message):
            message
        }
    }
}

enum HomeMapKoreanCopy {
    static let readyMessage = "시연용 기본 위치의 지도 후보를 준비합니다."
    static let loadingMessage = "지도 안 후보와 추천 이유를 정리하고 있습니다."
    static let emptyMessage = "지도를 움직이거나 반경을 넓혀 추천 후보를 다시 확인해 주세요."
}

private struct RandomMapResultSheet: View {
    let card: RecommendationCardModel
    let mode: RecommendationPickerMode
    let visiblePoolCount: Int
    let reroll: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: mode.symbolName)
                    .font(.title3)
                    .foregroundStyle(.secondary)
                    .frame(width: 32, height: 32)
                    .background(Color.secondary.opacity(0.10), in: Circle())

                VStack(alignment: .leading, spacing: 5) {
                    Text("후보 \(visiblePoolCount)개 중 선택")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(card.title)
                        .font(.title3.weight(.semibold))
                        .lineLimit(2)
                    Text(mode.resultCopy(for: card))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(3)
                }
            }

            FlowMetadataRow(card: card)

            HStack(spacing: 10) {
                Button(action: reroll) {
                    Label("다시", systemImage: "shuffle")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)

                NavigationLink(value: AppRoute.recommendationDetail(cardID: card.id)) {
                    Label("이유", systemImage: "info.circle")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(16)
        .nativePanel(cornerRadius: 20)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(card.mapFirstAccessibilitySummary)
    }
}

struct FlowMetadataRow: View {
    let card: RecommendationCardModel

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 6) { chips }
            VStack(alignment: .leading, spacing: 6) { chips }
        }
    }

    @ViewBuilder
    private var chips: some View {
        MetadataChip(text: card.distanceLabel, systemImage: "figure.walk")
        MetadataChip(text: card.district, systemImage: "mappin.and.ellipse")
        MetadataChip(text: card.category, systemImage: "tag")
        if let themeTag = card.tags.first {
            MetadataChip(text: themeTag, systemImage: "sparkle")
        }
    }
}

private struct MetadataChip: View {
    let text: String
    let systemImage: String

    var body: some View {
        Label(text, systemImage: systemImage)
            .font(.caption)
            .lineLimit(1)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(Color.secondary.opacity(0.08), in: Capsule())
    }
}

struct StateMessageView: View {
    let icon: String
    let title: String
    let message: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(title, systemImage: icon)
                .font(.headline)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
    }
}

private extension View {
    func nativePanel(cornerRadius: CGFloat) -> some View {
        background(.regularMaterial, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(.separator.opacity(0.35), lineWidth: 0.5)
            }
    }
}

private extension RecommendationCardModel {
    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }
}


#Preview {
    NavigationStack {
        HomeRecommendationScreen(viewModel: RecommendationViewModel(provider: PeroAPIProviderFactory.preview(), locationProvider: StaticLocationProvider.preview))
    }
}

import SwiftUI
import UIKit
import PeroCore

struct HomeRecommendationScreen: View {
    @ObservedObject var viewModel: RecommendationViewModel
    @State private var pickerMode: RecommendationPickerMode = .attraction
    @State private var selectedCardID: RecommendationCardModel.ID?
    @State private var rerollTask: Task<Void, Never>?
    @State private var drawTask: Task<Void, Never>?
    @State private var isDrawing = false
    @State private var highlightedCardID: RecommendationCardModel.ID?
    @State private var camera = KakaoMapCamera.seoul
    @State private var visibleBounds: KakaoMapVisibleBounds?

    private var candidateCards: [RecommendationCardModel] {
        candidates(for: pickerMode)
    }

    private var viewportCandidateCards: [RecommendationCardModel] {
        viewportCandidates(for: pickerMode)
    }

    private var hasAnyViewportCandidate: Bool {
        RecommendationPickerMode.allCases.contains { !viewportCandidates(for: $0).isEmpty }
    }

    private var selectedCard: RecommendationCardModel? {
        guard let selectedCardID,
              let card = viewModel.card(for: selectedCardID),
              pickerMode.matches(card) else {
            return nil
        }
        return card
    }

    private var mapMarkers: [KakaoMapMarker] {
        var markerCards = Array(viewportCandidateCards.prefix(350))
        if let selectedCard, !markerCards.contains(where: { $0.id == selectedCard.id }) {
            markerCards.append(selectedCard)
        }
        return markerCards.map { card in
            KakaoMapMarker(
                id: card.id,
                latitude: card.latitude,
                longitude: card.longitude,
                isSelected: selectedCard?.id == card.id || highlightedCardID == card.id
            )
        }
    }

    var body: some View {
        ZStack {
            mapCanvas
            overlayChrome
        }
        .background(PeroMapStyle.paper)
        .ignoresSafeArea(.container, edges: .bottom)
        .toolbar(.hidden, for: .navigationBar)
        .refreshable {
            await viewModel.loadGoNowRecommendations()
        }
        .onChange(of: viewModel.cards) { _, cards in
            reconcileSelection(with: cards)
        }
        .onChange(of: pickerMode) { _, _ in
            reconcileSelection(with: viewModel.cards)
        }
        .onChange(of: visibleBounds) { _, _ in
            guard !isDrawing else { return }
            reconcileSelection(with: viewModel.cards)
        }
        .onDisappear {
            rerollTask?.cancel()
            drawTask?.cancel()
        }
    }

    private var mapCanvas: some View {
        GeometryReader { proxy in
            KakaoMapView(camera: $camera, markers: mapMarkers) { bounds in
                visibleBounds = bounds
            }
                .frame(width: proxy.size.width, height: proxy.size.height)
                .ignoresSafeArea()
        }
        .ignoresSafeArea()
    }

    private var overlayChrome: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 0)
            bottomControls
        }
        .padding(.horizontal, 16)
        .safeAreaPadding(.bottom, 12)
    }

    private var bottomControls: some View {
        VStack(spacing: 10) {
            randomPickButton
            selectedResultSheet
        }
    }

    private var randomPickButton: some View {
        Menu {
            ForEach(RecommendationPickerMode.allCases) { mode in
                Button {
                    runMapDrawAnimation(mode: mode)
                } label: {
                    Label(mode.title, systemImage: mode.symbolName)
                }
                .disabled(viewportCandidates(for: mode).isEmpty)
            }
        } label: {
            randomPickButtonLabel
        }
        .buttonStyle(.borderedProminent)
        .buttonBorderShape(.capsule)
        .tint(PeroMapStyle.surface)
        .foregroundStyle(PeroMapStyle.ink)
        .overlay {
            Capsule().stroke(PeroMapStyle.accent, lineWidth: selectedCard == nil ? 2 : 1.2)
        }
        .disabled(viewModel.state == .loading || !hasAnyViewportCandidate || isDrawing)
        .opacity(viewModel.state == .loading || !hasAnyViewportCandidate || isDrawing ? 0.55 : 1)
        .accessibilityLabel(randomButtonTitle)
        .accessibilityIdentifier("mapRandomPickButton")
    }

    @ViewBuilder
    private var randomPickButtonLabel: some View {
        Label(randomButtonTitle, systemImage: viewModel.state == .loading ? "hourglass" : "sparkle")
            .font(selectedCard == nil ? .headline.weight(.semibold) : .subheadline.weight(.semibold))
            .padding(.horizontal, selectedCard == nil ? 0 : 16)
            .frame(maxWidth: selectedCard == nil ? .infinity : nil)
            .frame(height: selectedCard == nil ? 58 : 42)
            .fixedSize(horizontal: selectedCard != nil, vertical: false)
    }

    private var randomButtonTitle: String {
        switch viewModel.state {
        case .loading:
            "후보 찾는 중"
        default:
            if isDrawing {
                "뽑는 중"
            } else if !hasAnyViewportCandidate {
                "화면 안 후보 없음"
            } else if viewportCandidateCards.isEmpty {
                "종류 선택"
            } else {
                selectedCard == nil ? "\(pickerMode.title) 뽑기" : pickerMode.title
            }
        }
    }

    @ViewBuilder
    private var selectedResultSheet: some View {
        if let selectedCard {
            RandomMapResultSheet(
                card: selectedCard,
                mode: pickerMode
            )
            .transition(.move(edge: .bottom).combined(with: .opacity))
        } else if viewModel.state == .results, viewportCandidateCards.isEmpty {
            StateMessageView(
                icon: "map",
                title: "화면 안 후보 없음",
                message: HomeMapKoreanCopy.viewportEmptyMessage
            )
            .peroBottomSheetSurface()
        } else if viewModel.state != .results {
            StateMessageView(
                icon: stateIcon,
                title: viewModel.state.title,
                message: stateMessage
            )
            .peroBottomSheetSurface()
        }
    }

    private func rerollRecommendations() {
        rerollTask?.cancel()
        rerollTask = Task {
            await viewModel.loadGoNowRecommendations()
        }
    }

    private func runMapDrawAnimation(mode: RecommendationPickerMode) {
        pickerMode = mode
        selectedCardID = nil
        let pool = viewportCandidates(for: mode)
        guard !pool.isEmpty else {
            rerollRecommendations()
            return
        }
        drawTask?.cancel()
        drawTask = Task {
            await animateMapDraw(with: pool)
        }
    }

    private func candidates(for mode: RecommendationPickerMode) -> [RecommendationCardModel] {
        viewModel.cards.filter { mode.matches($0) }
    }

    private func viewportCandidates(for mode: RecommendationPickerMode) -> [RecommendationCardModel] {
        let cards = candidates(for: mode)
        guard let visibleBounds else { return cards }
        return cards.filter { visibleBounds.contains(latitude: $0.latitude, longitude: $0.longitude) }
    }

    private func reconcileSelection(with cards: [RecommendationCardModel]) {
        if let selectedCardID,
           cards.contains(where: { $0.id == selectedCardID && pickerMode.matches($0) }),
           selectedCard.map({ visibleBounds?.contains(latitude: $0.latitude, longitude: $0.longitude) ?? true }) == true {
            return
        }
        selectedCardID = nil
    }

    @MainActor
    private func animateMapDraw(with pool: [RecommendationCardModel]) async {
        isDrawing = true
        selectedCardID = nil

        let impact = UIImpactFeedbackGenerator(style: .light)
        let success = UINotificationFeedbackGenerator()
        impact.prepare()
        success.prepare()

        let run = drawRun(from: pool)
        for (index, card) in run.enumerated() {
            guard !Task.isCancelled else { break }
            highlightedCardID = card.id
            impact.impactOccurred(intensity: index == run.indices.last ? 0.75 : 0.38)
            try? await Task.sleep(for: .milliseconds(index == run.indices.last ? 260 : 190))
        }

        guard !Task.isCancelled, let finalCard = run.last else {
            highlightedCardID = nil
            isDrawing = false
            return
        }

        guard !Task.isCancelled else {
            highlightedCardID = nil
            isDrawing = false
            return
        }

        selectedCardID = finalCard.id
        highlightedCardID = nil
        isDrawing = false
        success.notificationOccurred(.success)
    }

    private func drawRun(from pool: [RecommendationCardModel]) -> [RecommendationCardModel] {
        let count = min(max(pool.count, 1), 5)
        let shuffled = pool.shuffled()
        if shuffled.count <= count {
            return shuffled
        }
        return Array(shuffled.prefix(count))
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
    static let loadingMessage = "지도 안 후보를 불러오고 있습니다."
    static let emptyMessage = "지도를 움직이거나 반경을 넓혀 추천 후보를 다시 확인해 주세요."
    static let viewportEmptyMessage = "지도를 축소하거나 다른 종류를 선택하세요."
}

private struct RandomMapResultSheet: View {
    let card: RecommendationCardModel
    let mode: RecommendationPickerMode

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 5) {
                    Label(mode.title, systemImage: mode.symbolName)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(PeroMapStyle.muted)
                    Text(card.title)
                        .font(.title3.weight(.bold))
                        .foregroundStyle(PeroMapStyle.ink)
                        .lineLimit(2)
                }
                Spacer(minLength: 8)
            }

            FlowMetadataRow(card: card)

            HStack(spacing: 10) {
                if let appleMapsURL = card.appleMapsURL {
                    Link(destination: appleMapsURL) {
                        Label("길찾기", systemImage: "arrow.triangle.turn.up.right.circle")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                }

                NavigationLink(value: AppRoute.recommendationDetail(cardID: card.id)) {
                    Label("상세", systemImage: "info.circle")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(PeroMapStyle.accentDeep)
            }
            .font(.subheadline.weight(.semibold))
        }
        .padding(.top, 22)
        .padding(.horizontal, 20)
        .padding(.bottom, 18)
        .peroBottomSheetSurface()
        .accessibilityLabel("랜덤 \(mode.title) 추천, \(card.title), \(card.district), \(card.category)")
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
        MetadataChip(text: card.district, systemImage: "mappin.and.ellipse")
        MetadataChip(text: card.category, systemImage: "tag")
    }
}

private struct MetadataChip: View {
    let text: String
    let systemImage: String

    var body: some View {
        Label(text, systemImage: systemImage)
            .font(.caption.weight(.semibold))
            .lineLimit(1)
            .foregroundStyle(PeroMapStyle.inkSoft)
            .padding(.horizontal, 9)
            .frame(height: 28)
            .background(PeroMapStyle.surfaceMuted, in: Capsule())
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
                .foregroundStyle(PeroMapStyle.ink)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(PeroMapStyle.inkSoft)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
    }
}

#Preview {
    NavigationStack {
        HomeRecommendationScreen(viewModel: RecommendationViewModel(provider: PeroAPIProviderFactory.preview(), locationProvider: StaticLocationProvider.preview))
    }
}

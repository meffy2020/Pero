import SwiftUI
import PeroCore

struct HomeRecommendationScreen: View {
    @ObservedObject var viewModel: RecommendationViewModel
    @State private var pickerMode: RecommendationPickerMode = .place
    @State private var selectedCardID: RecommendationCardModel.ID?
    @State private var rerollTask: Task<Void, Never>?
    @State private var camera = KakaoMapCamera.seoul
    @State private var pulseSelection = false

    private var candidateCards: [RecommendationCardModel] {
        viewModel.cards.filter { pickerMode.matches($0) }
    }

    private var visiblePoolCount: Int {
        candidateCards.count
    }

    private var selectedCard: RecommendationCardModel? {
        guard let selectedCardID,
              let card = viewModel.card(for: selectedCardID),
              pickerMode.matches(card) else {
            return nil
        }
        return card
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
        .onDisappear {
            rerollTask?.cancel()
        }
    }

    private var mapCanvas: some View {
        GeometryReader { proxy in
            ZStack {
                KakaoMapView(camera: camera)
                    .frame(width: proxy.size.width, height: proxy.size.height)
                    .ignoresSafeArea()

                ForEach(candidateCards) { card in
                    Button {
                        select(card)
                    } label: {
                        CandidateMarker(
                            card: card,
                            isSelected: selectedCard?.id == card.id,
                            mode: RecommendationPickerMode(card: card),
                            pulse: pulseSelection
                        )
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("\(card.title) 선택")
                    .position(markerPosition(for: card, in: proxy.size))
                }
            }
        }
        .ignoresSafeArea()
    }

    private var overlayChrome: some View {
        VStack(spacing: 0) {
            topFloatingControls
            Spacer(minLength: 0)
            bottomControls
        }
        .padding(.horizontal, 16)
        .safeAreaPadding(.top, 10)
        .safeAreaPadding(.bottom, 12)
    }

    private var topFloatingControls: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 10) {
                Spacer(minLength: 8)
                sideControls
            }

            modeChips
        }
    }

    private var sideControls: some View {
        VStack(spacing: 10) {
            MapFloatingButton(systemImage: "location.north.line") {
                recenterOnSelection()
            }
        }
    }

    private var modeChips: some View {
        HStack(spacing: 8) {
            ForEach(RecommendationPickerMode.allCases) { mode in
                Button {
                    pickerMode = mode
                } label: {
                    Label(mode.title, systemImage: mode.symbolName)
                        .font(.subheadline.weight(.semibold))
                        .labelStyle(.titleAndIcon)
                        .lineLimit(1)
                        .foregroundStyle(pickerMode == mode ? PeroMapStyle.ink : PeroMapStyle.inkSoft)
                        .padding(.horizontal, 14)
                        .frame(height: 40)
                        .background(pickerMode == mode ? PeroMapStyle.accentPale : PeroMapStyle.surface, in: Capsule())
                        .overlay {
                            Capsule().stroke(pickerMode == mode ? PeroMapStyle.accent : PeroMapStyle.line, lineWidth: 0.8)
                        }
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var bottomControls: some View {
        VStack(spacing: 10) {
            poolCaption
            selectedResultSheet
            randomPickButton
        }
    }

    private var poolCaption: some View {
        Text("현재 추천 영역 후보 \(visiblePoolCount)개" + (viewModel.fallbackUsed ? " · 반경 보완" : ""))
            .font(.caption.weight(.semibold))
            .foregroundStyle(PeroMapStyle.inkSoft)
            .padding(.horizontal, 12)
            .frame(height: 28)
            .background(PeroMapStyle.surface.opacity(0.92), in: Capsule())
            .overlay { Capsule().stroke(PeroMapStyle.line, lineWidth: 0.7) }
    }

    private var randomPickButton: some View {
        Button {
            pickRandomCandidate()
        } label: {
            Label(randomButtonTitle, systemImage: viewModel.state == .loading ? "hourglass" : "sparkle")
                .font(.headline.weight(.semibold))
                .foregroundStyle(PeroMapStyle.ink)
                .frame(maxWidth: .infinity)
                .frame(height: 58)
                .background(PeroMapStyle.surface, in: Capsule())
                .overlay {
                    Capsule().stroke(PeroMapStyle.accent, lineWidth: 2)
                }
        }
        .buttonStyle(.plain)
        .disabled(viewModel.state == .loading || candidateCards.isEmpty)
        .opacity(viewModel.state == .loading || candidateCards.isEmpty ? 0.55 : 1)
        .accessibilityIdentifier("mapRandomPickButton")
    }

    private var randomButtonTitle: String {
        switch viewModel.state {
        case .loading:
            "후보 찾는 중"
        default:
            selectedCard == nil ? "랜덤 뽑기" : "다시 뽑기"
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

    private func pickRandomCandidate() {
        withAnimation(.easeInOut(duration: 0.45)) {
            pulseSelection.toggle()
        }
        if let random = candidateCards.randomElement() {
            select(random)
            return
        }
        rerollRecommendations()
    }

    private func select(_ card: RecommendationCardModel) {
        selectedCardID = card.id
        camera = KakaoMapCamera(latitude: card.latitude, longitude: card.longitude, level: 5)
    }

    private func recenterOnSelection() {
        if let selectedCard {
            select(selectedCard)
        } else if let first = candidateCards.first {
            camera = KakaoMapCamera(latitude: first.latitude, longitude: first.longitude, level: 7)
        }
    }

    private func markerPosition(for card: RecommendationCardModel, in size: CGSize) -> CGPoint {
        let longitudeDelta = max(min(card.longitude - camera.longitude, 0.03), -0.03)
        let latitudeDelta = max(min(card.latitude - camera.latitude, 0.03), -0.03)
        let scale = max(size.width, size.height) * 10
        return CGPoint(
            x: size.width / 2 + longitudeDelta * scale,
            y: size.height / 2 - latitudeDelta * scale
        )
    }

    private func reconcileSelection(with cards: [RecommendationCardModel]) {
        if let selectedCardID,
           cards.contains(where: { $0.id == selectedCardID && pickerMode.matches($0) }) {
            return
        }
        selectedCardID = nil
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
}

private struct CandidateMarker: View {
    let card: RecommendationCardModel
    let isSelected: Bool
    let mode: RecommendationPickerMode
    let pulse: Bool

    var body: some View {
        VStack(spacing: 5) {
            ZStack {
                if isSelected {
                    Circle()
                        .stroke(PeroMapStyle.accent, lineWidth: 3)
                        .frame(width: pulse ? 44 : 34, height: pulse ? 44 : 34)
                        .opacity(pulse ? 0.22 : 0.55)
                }
                Circle()
                    .fill(isSelected ? PeroMapStyle.surface : PeroMapStyle.ink)
                    .frame(width: isSelected ? 24 : 12, height: isSelected ? 24 : 12)
                    .overlay {
                        Circle().stroke(isSelected ? PeroMapStyle.accentDeep : PeroMapStyle.surface, lineWidth: isSelected ? 3 : 2)
                    }
            }
            if isSelected {
                Text(card.title)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(PeroMapStyle.ink)
                    .lineLimit(1)
                    .padding(.horizontal, 8)
                    .frame(height: 26)
                    .peroFloatingSurface(cornerRadius: 13)
            }
        }
        .animation(.easeInOut(duration: 0.35), value: isSelected)
        .animation(.easeInOut(duration: 0.45), value: pulse)
    }
}

private struct MapFloatingButton: View {
    let systemImage: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.headline.weight(.semibold))
                .foregroundStyle(PeroMapStyle.ink)
                .frame(width: 46, height: 46)
        }
        .buttonStyle(.plain)
        .peroFloatingSurface(cornerRadius: 23)
    }
}

private struct RandomMapResultSheet: View {
    let card: RecommendationCardModel
    let mode: RecommendationPickerMode
    let visiblePoolCount: Int
    let reroll: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 5) {
                    Text("\(mode.title) · 후보 \(visiblePoolCount)개")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(PeroMapStyle.muted)
                    Text(card.title)
                        .font(.title3.weight(.bold))
                        .foregroundStyle(PeroMapStyle.ink)
                        .lineLimit(2)
                }
                Spacer(minLength: 8)
                Image(systemName: mode.symbolName)
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(PeroMapStyle.ink)
                    .frame(width: 38, height: 38)
                    .background(PeroMapStyle.accentPale, in: Circle())
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

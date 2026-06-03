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
                        VStack(spacing: 5) {
                            Image(systemName: markerSymbol(for: card))
                                .font(.system(size: selectedCard?.id == card.id ? 32 : 24, weight: .bold))
                                .foregroundStyle(.white, markerTint(for: card).gradient)
                                .shadow(color: .black.opacity(0.20), radius: 8, y: 4)
                            if selectedCard?.id == card.id {
                                Text(card.title)
                                    .font(.caption2.weight(.bold))
                                    .foregroundStyle(.primary)
                                    .lineLimit(1)
                                    .padding(.horizontal, 9)
                                    .padding(.vertical, 5)
                                    .homeRecommendationGlass(cornerRadius: 12, tint: .white.opacity(0.28))
                            }
                        }
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("\(card.title) 선택")
                }
            }
        }
        .mapStyle(.standard(elevation: .realistic, pointsOfInterest: .including([.park, .restaurant, .museum])))
        .overlay {
            LinearGradient(
                colors: [.black.opacity(0.18), .clear, .black.opacity(0.28)],
                startPoint: .top,
                endPoint: .bottom
            )
            .allowsHitTesting(false)
        }
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
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 10) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("지금 뭐 하지?")
                        .font(.largeTitle.weight(.black))
                        .foregroundStyle(.primary)
                    Text("보고 있는 지도 안 후보만 랜덤으로 뽑아요")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                Label(viewModel.locationLabel, systemImage: "location.fill")
                    .font(.caption.weight(.bold))
                    .lineLimit(2)
                    .foregroundStyle(.blue)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .homeRecommendationGlass(cornerRadius: 16, tint: .cyan.opacity(0.20))
            }

            HStack(spacing: 8) {
                ForEach(RecommendationPickerMode.allCases) { mode in
                    Button {
                        pickerMode = mode
                    } label: {
                        Label(mode.title, systemImage: mode.symbolName)
                            .font(.caption.weight(.bold))
                            .lineLimit(1)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 9)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(pickerMode == mode ? .white : mode.accent)
                    .background(pickerMode == mode ? mode.accent : mode.accent.opacity(0.12), in: Capsule())
                }
            }
        }
        .padding(16)
        .homeRecommendationGlass(cornerRadius: 28, tint: .white.opacity(0.30), interactive: true)
        .shadow(color: .black.opacity(0.10), radius: 18, y: 10)
    }

    private var currentAreaPill: some View {
        HStack(spacing: 8) {
            Label("현재 화면 안 후보 \(visiblePoolCount)개", systemImage: "scope")
            Text("·")
                .foregroundStyle(.tertiary)
            Text(pickerMode.poolCopy)
            if viewModel.fallbackUsed {
                Text("· 반경 보완")
                    .foregroundStyle(.secondary)
            }
        }
        .font(.caption.weight(.bold))
        .lineLimit(1)
        .minimumScaleFactor(0.8)
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .homeRecommendationGlass(cornerRadius: 18, tint: .white.opacity(0.34))
        .padding(.bottom, 10)
    }

    private var randomPickButton: some View {
        Button {
            pickRandomCandidate()
        } label: {
            HStack(spacing: 10) {
                Image(systemName: viewModel.state == .loading ? "hourglass" : "sparkles")
                Text(randomButtonTitle)
                Image(systemName: "shuffle")
            }
            .font(.headline.weight(.black))
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(pickerMode.accent.gradient, in: Capsule())
            .shadow(color: pickerMode.accent.opacity(0.36), radius: 20, y: 10)
        }
        .buttonStyle(.plain)
        .disabled(viewModel.state == .loading || candidateCards.isEmpty)
        .opacity(viewModel.state == .loading || candidateCards.isEmpty ? 0.68 : 1)
        .padding(.bottom, 12)
        .accessibilityIdentifier("mapRandomPickButton")
    }

    private var randomButtonTitle: String {
        switch viewModel.state {
        case .loading:
            "후보 스캔 중"
        default:
            "이 화면에서 \(pickerMode.shortTitle) 랜덤 PICK"
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
            .homeRecommendationGlass(cornerRadius: 28, tint: .white.opacity(0.22))
        }
    }

    private var stateIcon: String {
        switch viewModel.state {
        case .ready: "location"
        case .loading: "hourglass"
        case .results: "map"
        case .empty: "tray"
        case .error: "exclamationmark.triangle"
        }
    }

    private var stateMessage: String {
        switch viewModel.state {
        case .ready:
            "시연용 기본 위치로 지도 후보를 준비합니다."
        case .loading:
            "장소 핀과 추천 이유를 지도 위에 올리는 중입니다."
        case .results:
            "지도 후보를 선택하거나 랜덤 PICK을 눌러 주세요."
        case .empty:
            "현재 영역에 뽑을 후보가 없습니다. 추천 반경이나 백엔드 데이터를 확인해 주세요."
        case .error(let message):
            message
        }
    }

    private func markerSymbol(for card: RecommendationCardModel) -> String {
        RecommendationPickerMode(card: card).symbolName
    }

    private func markerTint(for card: RecommendationCardModel) -> Color {
        RecommendationPickerMode(card: card).accent
    }

    private func reconcileSelection(with cards: [RecommendationCardModel]) {
        if let selectedCardID,
           let card = cards.first(where: { $0.id == selectedCardID }),
           pickerMode.matches(card) {
            focus(on: card)
            return
        }
        if let replacement = cards.first(where: pickerMode.matches) ?? cards.first {
            select(replacement)
        } else {
            selectedCardID = nil
        }
    }

    private func pickRandomCandidate() {
        if candidateCards.isEmpty {
            rerollRecommendations()
            return
        }
        if candidateCards.count == 1, let only = candidateCards.first {
            select(only)
            return
        }
        let currentID = selectedCardID
        let next = candidateCards.filter { $0.id != currentID }.randomElement() ?? candidateCards.randomElement()
        if let next {
            select(next)
        }
    }

    private func select(_ card: RecommendationCardModel) {
        selectedCardID = card.id
        focus(on: card)
    }

    private func focus(on card: RecommendationCardModel) {
        withAnimation(.spring(response: 0.45, dampingFraction: 0.86)) {
            cameraPosition = .region(
                MKCoordinateRegion(
                    center: card.coordinate,
                    span: MKCoordinateSpan(latitudeDelta: 0.018, longitudeDelta: 0.018)
                )
            )
        }
    }

    private func rerollRecommendations() {
        rerollTask?.cancel()
        rerollTask = Task {
            await viewModel.loadGoNowRecommendations()
        }
    }
}

private struct RandomMapResultSheet: View {
    let card: RecommendationCardModel
    let mode: RecommendationPickerMode
    let visiblePoolCount: Int
    let reroll: () -> Void

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            Map(initialPosition: position) {
                if let card {
                    Marker(card.title, coordinate: CLLocationCoordinate2D(latitude: card.latitude, longitude: card.longitude))
                }
            }
            .mapStyle(.standard(elevation: .realistic))
            .allowsHitTesting(false)
            .overlay {
                LinearGradient(
                    colors: [.black.opacity(0.05), .black.opacity(0.45)],
                    startPoint: .top,
                    endPoint: .bottom
                )
            }

            VStack(alignment: .leading, spacing: 8) {
                Label("지도 우선 탐색", systemImage: "map")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.white.opacity(0.88))
                Text(card?.title ?? "추천 지도를 준비 중입니다")
                    .font(.title3.weight(.bold))
                    .foregroundStyle(.white)
                if let card {
                    HStack(spacing: 6) {
                        MetadataChip(text: card.distanceLabel, systemImage: "figure.walk", style: .light)
                        MetadataChip(text: card.district, systemImage: "mappin.and.ellipse", style: .light)
                    }
                }
            }
            .padding(16)
        }
        .overlay(alignment: .topTrailing) {
            VStack(spacing: 8) {
                Image(systemName: "location.north.line.fill")
                Image(systemName: "plus.magnifyingglass")
            }
            .font(.caption.weight(.bold))
            .foregroundStyle(.primary)
            .padding(10)
            .homeRecommendationGlass(cornerRadius: 18, tint: .white.opacity(0.22))
            .padding(12)
        }
    }
}

private struct RandomRecommendationSlotCard: View {
    let slot: RandomRecommendationSlot
    let card: RecommendationCardModel?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 7) {
                    Label("현재 화면에서 뽑힘 · 후보 \(visiblePoolCount)개", systemImage: "scope")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(mode.accent)
                    Text(card.title)
                        .font(.title2.weight(.black))
                        .lineLimit(2)
                    Text(mode.resultCopy(for: card))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 8)
                Image(systemName: mode.symbolName)
                    .font(.title2.weight(.bold))
                    .foregroundStyle(mode.accent)
                    .frame(width: 48, height: 48)
                    .homeRecommendationGlass(cornerRadius: 18, tint: mode.accent.opacity(0.16))
            }

            FlowMetadataRow(card: card)

            HStack(spacing: 10) {
                Button(action: reroll) {
                    Label("다시 뽑기", systemImage: "shuffle")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(mode.accent)

                if let appleMapsURL = card.appleMapsURL {
                    Link(destination: appleMapsURL) {
                        Label("길찾기", systemImage: "arrow.triangle.turn.up.right.circle.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                }

                NavigationLink(value: AppRoute.recommendationDetail(cardID: card.id)) {
                    Label("상세", systemImage: "sparkles")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
            }
            .font(.caption.weight(.bold))
        }
        .padding(18)
        .homeRecommendationGlass(cornerRadius: 30, tint: .white.opacity(0.36), interactive: true)
        .shadow(color: .black.opacity(0.16), radius: 24, y: 14)
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
    enum Style {
        case normal
        case light
    }

    let text: String
    let systemImage: String
    var style: Style = .normal

    var body: some View {
        Label(text, systemImage: systemImage)
            .font(.caption.weight(.semibold))
            .lineLimit(1)
            .foregroundStyle(style == .light ? .white : .secondary)
            .padding(.horizontal, 9)
            .padding(.vertical, 6)
            .background(style == .light ? Color.white.opacity(0.18) : Color.primary.opacity(0.06), in: Capsule())
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
    @ViewBuilder
    func homeRecommendationGlass(cornerRadius: CGFloat, tint: Color? = nil, interactive: Bool = false) -> some View {
        if #available(iOS 26, *) {
            let glass = interactive ? Glass.regular.tint(tint).interactive() : Glass.regular.tint(tint)

            self
                .glassEffect(glass, in: .rect(cornerRadius: cornerRadius))
        } else {
            let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)

            self
                .background {
                    shape.fill(.ultraThinMaterial)
                    if let tint {
                        shape.fill(tint)
                    }
                }
                .overlay {
                    shape.stroke(.quaternary, lineWidth: 1)
                }
        }
    }
}

private extension RecommendationCardModel {
    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }
}

private extension RecommendationPickerMode {
    var accent: Color {
        switch self {
        case .place: .blue
        case .restaurant: .orange
        case .course: .purple
        }
    }
}

#Preview {
    NavigationStack {
        HomeRecommendationScreen(viewModel: RecommendationViewModel(provider: PeroAPIProviderFactory.preview(), locationProvider: StaticLocationProvider.preview))
    }
}

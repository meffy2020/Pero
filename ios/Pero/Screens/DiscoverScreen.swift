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
                    Text("현재 추천 영역 안 후보만 랜덤으로 뽑아요")
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
            Label("현재 추천 영역 후보 \(visiblePoolCount)개", systemImage: "scope")
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
            "이 영역에서 \(pickerMode.shortTitle) 랜덤 PICK"
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

    private var heroSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label(viewModel.locationLabel, systemImage: "location.fill")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.blue)
                .lineLimit(1)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .homeRecommendationGlass(cornerRadius: 16, tint: .cyan.opacity(0.24))

            VStack(alignment: .leading, spacing: 8) {
                Text("지금 뭐 하지?")
                    .font(.largeTitle.weight(.bold))
                    .minimumScaleFactor(0.82)
                Text(HomeMapKoreanCopy.heroSubtitle)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack(spacing: 10) {
                Button {
                    rerollRecommendations()
                } label: {
                    Label(viewModel.state == .loading ? HomeMapKoreanCopy.randomPickLoadingCTA : HomeMapKoreanCopy.randomPickCTA, systemImage: "arrow.triangle.2.circlepath")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(viewModel.state == .loading)

                Text(HomeMapKoreanCopy.randomPickHint)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            if viewModel.fallbackUsed {
                Label(HomeMapKoreanCopy.fallbackNotice, systemImage: "info.circle")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .homeRecommendationGlass(cornerRadius: 14, tint: .white.opacity(0.18))
            }
        }
    }

    private var randomSlotSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionTitle(HomeMapKoreanCopy.slotSectionTitle)
            ForEach(RandomRecommendationSlot.all) { slot in
                RandomRecommendationSlotCard(slot: slot, card: viewModel.card(forSlotTitle: slot.title))
            }
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

    private func markerTint(for card: RecommendationCardModel) -> Color {
        RecommendationPickerMode(card: card).accent
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

    @ViewBuilder
    private var stateSection: some View {
        switch viewModel.state {
        case .ready:
            StateMessageView(icon: "location", title: "위치 확인 대기", message: HomeMapKoreanCopy.readyMessage)
        case .loading:
            VStack(alignment: .leading, spacing: 10) {
                SectionTitle("지금 갈 곳 찾는 중")
                HStack(spacing: 12) {
                    ProgressView()
                    Text(HomeMapKoreanCopy.loadingMessage)
                        .foregroundStyle(.secondary)
                }
                .padding(16)
                .homeRecommendationGlass(cornerRadius: 20, tint: .white.opacity(0.18))
            }
        case .results:
            EmptyView()
        case .empty:
            StateMessageView(icon: "tray", title: "추천 후보 없음", message: HomeMapKoreanCopy.emptyMessage)
        case .error(let message):
            StateMessageView(icon: "exclamationmark.triangle", title: "연결 확인 필요", message: message)
        }
    }

}



enum HomeMapKoreanCopy {
    static let heroSubtitle = "현재 보고 있는 지도 안 후보에서 장소·식당·코스를 바로 뽑고, 왜 추천됐는지는 카드에서 확인해요."
    static let randomPickCTA = "이 화면에서 랜덤 픽"
    static let randomPickLoadingCTA = "지도 후보 뽑는 중"
    static let randomPickHint = "검색 조건을 바꾸지 않고 현재 화면의 추천 후보만 새로 뽑습니다."
    static let fallbackNotice = "현재 화면 후보가 부족해 주변 반경을 넓힌 결과입니다"
    static let slotSectionTitle = "현재 화면 안 추천 후보"
    static let readyMessage = "시연용 기본 위치의 지도 후보를 준비합니다."
    static let loadingMessage = "지도 안 후보와 추천 이유를 정리하고 있습니다."
    static let emptyMessage = "지도를 움직이거나 반경을 넓혀 추천 후보를 다시 확인해 주세요."
    static let mapPreviewEyebrow = "현재 화면 후보"
    static let mapPreviewPlaceholder = "지도 후보를 준비 중입니다"
    static let mapCTA = "지도에서 보기"
    static let reasonCTA = "왜 뽑혔는지 보기"
    static let slotPendingMessage = "랜덤 픽을 누르거나 추천 응답이 도착하면 이 슬롯이 채워집니다."
}

private struct RandomRecommendationSlot: Identifiable {
    let id: String
    let title: String
    let userPrompt: String
    let systemImage: String
    let tint: Color

    static let all = [
        RandomRecommendationSlot(
            id: "nearby",
            title: "랜덤 장소 추천",
            userPrompt: "현재 화면 안에서 하나만 골라줘",
            systemImage: "shuffle.circle.fill",
            tint: .blue
        ),
        RandomRecommendationSlot(
            id: "meal",
            title: "식당 추천",
            userPrompt: "이 지도 안에서 밥 먹을 곳 골라줘",
            systemImage: "fork.knife.circle.fill",
            tint: .orange
        ),
        RandomRecommendationSlot(
            id: "course",
            title: "랜덤 코스 추천",
            userPrompt: "보이는 후보로 코스 짜줘",
            systemImage: "point.topleft.down.curvedto.point.bottomright.up.fill",
            tint: .purple
        )
    ]
}

private struct MapPreviewCard: View {
    let card: RecommendationCardModel?

    private var position: MapCameraPosition {
        guard let card else {
            return .region(
                MKCoordinateRegion(
                    center: CLLocationCoordinate2D(latitude: 37.5665, longitude: 126.9780),
                    span: MKCoordinateSpan(latitudeDelta: 0.08, longitudeDelta: 0.08)
                )
            )
        }
        return .region(
            MKCoordinateRegion(
                center: CLLocationCoordinate2D(latitude: card.latitude, longitude: card.longitude),
                span: MKCoordinateSpan(latitudeDelta: 0.018, longitudeDelta: 0.018)
            )
        )
    }

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
                Label(HomeMapKoreanCopy.mapPreviewEyebrow, systemImage: "map")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.white.opacity(0.88))
                Text(card?.title ?? HomeMapKoreanCopy.mapPreviewPlaceholder)
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
            .foregroundStyle(.primary)
            .padding(10)
            .homeRecommendationGlass(cornerRadius: 18, tint: .white.opacity(0.22))
            .padding(12)
        }
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
                VStack(alignment: .leading, spacing: 7) {
                    Label("현재 추천 영역에서 뽑힘 · 후보 \(visiblePoolCount)개", systemImage: "scope")
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

                NavigationLink(value: AppRoute.recommendationDetail(cardID: card.id)) {
                    Label(HomeMapKoreanCopy.reasonCTA, systemImage: "sparkles")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
            }
            .font(.caption.weight(.semibold))
        }
        .padding(18)
        .homeRecommendationGlass(cornerRadius: 30, tint: .white.opacity(0.36), interactive: true)
        .shadow(color: .black.opacity(0.16), radius: 24, y: 14)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(card.mapFirstAccessibilitySummary)
    }
}

private struct RandomRecommendationSlotCard: View {
    let slot: RandomRecommendationSlot
    let card: RecommendationCardModel?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 7) {
                    Label(slot.title, systemImage: slot.systemImage)
                        .font(.caption.weight(.bold))
                        .foregroundStyle(slot.tint)
                    Text(slot.userPrompt)
                        .font(.headline.weight(.bold))
                    if let card {
                        Text(card.reason)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    } else {
                        Text(HomeMapKoreanCopy.slotPendingMessage)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer(minLength: 8)
                Image(systemName: slot.systemImage)
                    .font(.title2.weight(.bold))
                    .foregroundStyle(slot.tint)
                    .frame(width: 46, height: 46)
                    .homeRecommendationGlass(cornerRadius: 16, tint: slot.tint.opacity(0.14))
            }

            if let card {
                FlowMetadataRow(card: card)

                HStack(spacing: 10) {
                    NavigationLink(value: AppRoute.mapFocus(cardID: card.id)) {
                        Label(HomeMapKoreanCopy.mapCTA, systemImage: "map")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)

                    NavigationLink(value: AppRoute.recommendationDetail(cardID: card.id)) {
                        Label(HomeMapKoreanCopy.reasonCTA, systemImage: "sparkles")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                }
                .font(.caption.weight(.semibold))
            } else {
                StateMessageView(
                    icon: "clock",
                    title: "추천 준비 중",
                    message: HomeMapKoreanCopy.slotPendingMessage
                )
            }
        }
        .padding(16)
        .homeRecommendationGlass(cornerRadius: 24, tint: .white.opacity(0.24))
    }
}

private struct SectionTitle: View {
    let text: String

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        Text(text)
            .font(.headline.weight(.bold))
            .frame(maxWidth: .infinity, alignment: .leading)
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

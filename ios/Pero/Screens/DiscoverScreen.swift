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
    @State private var isLocating = false
    @State private var drawPreviewTitle: String?
    @State private var locationFeedback: String?
    @State private var currentUserCoordinate: UserCoordinate?
    @State private var didCenterOnInitialLocation = false
    @State private var camera = KakaoMapCamera.seoul
    @State private var visibleBounds: KakaoMapVisibleBounds?

    private var viewportCandidateCards: [RecommendationCardModel] {
        viewportCandidates(for: pickerMode)
    }

    private var isViewportReady: Bool {
        visibleBounds != nil
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
        var markerCards = markerLayerCards
        if let selectedCard, !markerCards.contains(where: { $0.id == selectedCard.id }) {
            markerCards.append(selectedCard)
        }
        var markers = markerCards.map { card in
            KakaoMapMarker(
                id: card.id,
                latitude: card.latitude,
                longitude: card.longitude,
                isSelected: selectedCard?.id == card.id
            )
        }
        if let currentUserCoordinate {
            markers.append(
                KakaoMapMarker(
                    id: "current-user-location",
                    latitude: currentUserCoordinate.latitude,
                    longitude: currentUserCoordinate.longitude,
                    isSelected: false,
                    isUserLocation: true
                )
            )
        }
        return markers
    }

    private var markerLayerCards: [RecommendationCardModel] {
        guard shouldRenderAllVisibleMarkers else { return [] }
        return viewportCandidateCards
    }

    private var shouldRenderAllVisibleMarkers: Bool {
        guard let visibleBounds else { return false }
        return visibleBounds.isReadableMarkerDensity(for: viewportCandidateCards.count)
    }

    var body: some View {
        ZStack {
            mapCanvas
            drawCenterOverlay
            overlayChrome
        }
        .background(PeroMapStyle.paper)
        .ignoresSafeArea(.container, edges: .bottom)
        .toolbar(.hidden, for: .navigationBar)
        .refreshable {
            await viewModel.loadGoNowRecommendations()
        }
        .onAppear {
            centerOnInitialLocationIfNeeded(viewModel.activeCenterCoordinate)
        }
        .onChange(of: viewModel.cards) { _, cards in
            reconcileSelection(with: cards)
        }
        .onChange(of: viewModel.activeCenterCoordinate) { _, coordinate in
            centerOnInitialLocationIfNeeded(coordinate)
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
        .safeAreaPadding(.bottom, 34)
    }

    @ViewBuilder
    private var drawCenterOverlay: some View {
        if isDrawing, let drawPreviewTitle {
            VStack(spacing: 10) {
                Label("고르는 중", systemImage: "sparkles")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(PeroMapStyle.muted)
                Text(drawPreviewTitle)
                    .font(.title3.weight(.bold))
                    .foregroundStyle(PeroMapStyle.ink)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                    .id(drawPreviewTitle)
                    .transition(.opacity.combined(with: .scale(scale: 0.96)))
            }
            .padding(.horizontal, 22)
            .padding(.vertical, 18)
            .frame(maxWidth: 260)
            .background(PeroMapStyle.surface, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .stroke(PeroMapStyle.accent, lineWidth: 1.4)
            }
            .shadow(color: .black.opacity(0.14), radius: 18, y: 8)
            .transition(.opacity.combined(with: .scale(scale: 0.92)))
            .accessibilityElement(children: .combine)
            .accessibilityLabel("뽑는 중, \(drawPreviewTitle)")
        }
    }

    private var bottomControls: some View {
        VStack(spacing: 10) {
            HStack(alignment: .center, spacing: 8) {
                Spacer(minLength: 0)
                locationFeedbackPill
                currentLocationButton
            }
            drawControlRow
            selectedResultSheet
        }
    }

    @ViewBuilder
    private var locationFeedbackPill: some View {
        if let locationFeedback {
            Text(locationFeedback)
                .font(.caption.weight(.semibold))
                .foregroundStyle(PeroMapStyle.ink)
                .padding(.horizontal, 12)
                .frame(height: 34)
                .background(PeroMapStyle.surface, in: Capsule())
                .overlay {
                    Capsule().stroke(PeroMapStyle.line, lineWidth: 0.8)
                }
                .transition(.opacity.combined(with: .move(edge: .trailing)))
        }
    }

    private var currentLocationButton: some View {
        Button(action: focusCurrentLocation) {
            ZStack {
                Circle()
                    .fill(PeroMapStyle.surface)
                    .frame(width: 44, height: 44)
                if isLocating {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Image(systemName: "location.fill")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(PeroMapStyle.ink)
                }
            }
            .overlay {
                Circle().stroke(PeroMapStyle.line, lineWidth: 0.8)
            }
            .shadow(color: .black.opacity(0.12), radius: 10, y: 4)
        }
        .disabled(isLocating)
        .accessibilityLabel("현재 위치로 이동")
        .accessibilityIdentifier("currentLocationButton")
    }

    private var drawControlRow: some View {
        HStack(spacing: 0) {
            categoryMenuSegment
            Rectangle()
                .fill(PeroMapStyle.line)
                .frame(width: 1, height: selectedCard == nil ? 28 : 22)
            drawButtonSegment
        }
        .fixedSize(horizontal: true, vertical: false)
        .frame(height: selectedCard == nil ? 44 : 38)
        .background(PeroMapStyle.surface, in: Capsule())
        .overlay {
            Capsule().stroke(PeroMapStyle.accent, lineWidth: selectedCard == nil ? 2 : 1.2)
        }
        .opacity(viewModel.state == .loading || !isViewportReady || viewportCandidateCards.isEmpty || isDrawing ? 0.55 : 1)
        .accessibilityElement(children: .contain)
    }

    private var categoryMenuSegment: some View {
        Menu {
            ForEach(RecommendationPickerMode.allCases) { mode in
                Button {
                    pickerMode = mode
                    selectedCardID = nil
                    drawPreviewTitle = nil
                } label: {
                    Label(mode.title, systemImage: mode.symbolName)
                }
            }
        } label: {
            HStack(spacing: 4) {
                Text(pickerMode.title)
                Text("⌄")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(PeroMapStyle.muted)
            }
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(PeroMapStyle.ink)
            .padding(.leading, 16)
            .padding(.trailing, 12)
            .frame(height: selectedCard == nil ? 44 : 38)
        }
        .disabled(viewModel.state == .loading || isDrawing)
        .accessibilityLabel("뽑기 종류")
        .accessibilityValue(pickerMode.title)
        .accessibilityIdentifier("categorySwitchButton")
    }

    private var drawButtonSegment: some View {
        Button(action: runMapDrawAnimation) {
            Text(drawActionTitle)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(PeroMapStyle.ink)
                .padding(.leading, 12)
                .padding(.trailing, 16)
                .frame(height: selectedCard == nil ? 44 : 38)
        }
        .disabled(viewModel.state == .loading || !isViewportReady || viewportCandidateCards.isEmpty || isDrawing)
        .accessibilityLabel(randomButtonTitle)
        .accessibilityIdentifier("mapRandomPickButton")
    }

    private var randomButtonTitle: String {
        switch viewModel.state {
        case .loading:
            "후보 찾는 중"
        default:
            if isDrawing {
                "고르는 중"
            } else if !isViewportReady {
                "지도 준비 중"
            } else if viewportCandidateCards.isEmpty {
                "화면 안 후보 없음"
            } else {
                "\(pickerMode.title) 뽑기"
            }
        }
    }

    private var drawActionTitle: String {
        if isDrawing { return "고르는 중" }
        if viewModel.state == .loading { return "준비 중" }
        if !isViewportReady { return "준비 중" }
        return "뽑기"
    }

    @ViewBuilder
    private var selectedResultSheet: some View {
        if let selectedCard {
            RandomMapResultSheet(
                card: selectedCard
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


    private func centerOnInitialLocationIfNeeded(_ coordinate: UserCoordinate?) {
        guard !didCenterOnInitialLocation, let coordinate else { return }
        didCenterOnInitialLocation = true
        currentUserCoordinate = coordinate
        camera = KakaoMapCamera(
            latitude: coordinate.latitude,
            longitude: coordinate.longitude,
            level: KakaoMapCamera.focusedLevel
        )
    }

    private func rerollRecommendations() {
        rerollTask?.cancel()
        rerollTask = Task {
            await viewModel.loadGoNowRecommendations()
        }
    }

    private func focusCurrentLocation() {
        guard !isLocating else { return }
        isLocating = true
        selectedCardID = nil
        withAnimation(.snappy(duration: 0.16)) {
            locationFeedback = "현재 위치 확인 중"
        }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        Task {
            do {
                let coordinate = try await viewModel.currentCoordinate()
                await moveMapToCurrentLocation(coordinate)
                await refreshRecommendationsNearCurrentLocation(coordinate)
            } catch {
                isLocating = false
                withAnimation(.snappy(duration: 0.16)) {
                    locationFeedback = "위치 권한 확인 필요"
                }
                UINotificationFeedbackGenerator().notificationOccurred(.error)
                try? await Task.sleep(for: .milliseconds(1400))
                withAnimation(.snappy(duration: 0.16)) {
                    locationFeedback = nil
                }
            }
        }
    }

    @MainActor
    private func moveMapToCurrentLocation(_ coordinate: UserCoordinate) async {
        currentUserCoordinate = coordinate
        withAnimation(.snappy(duration: 0.18)) {
            locationFeedback = "현재 위치로 이동"
            camera = KakaoMapCamera(latitude: coordinate.latitude, longitude: coordinate.longitude, level: KakaoMapCamera.focusedLevel)
        }
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        isLocating = false
    }

    private func refreshRecommendationsNearCurrentLocation(_ coordinate: UserCoordinate) async {
        await viewModel.loadGoNowRecommendations(center: coordinate)
        try? await Task.sleep(for: .milliseconds(800))
        await MainActor.run {
            withAnimation(.snappy(duration: 0.16)) {
                locationFeedback = nil
            }
        }
    }

    private func runMapDrawAnimation() {
        selectedCardID = nil
        let pool = viewportCandidateCards
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
        guard let visibleBounds else { return [] }
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
        drawPreviewTitle = nil

        let impact = UIImpactFeedbackGenerator(style: .light)
        let success = UINotificationFeedbackGenerator()
        impact.prepare()
        success.prepare()

        let run = drawRun(from: pool)
        for (index, card) in run.enumerated() {
            guard !Task.isCancelled else { break }
            withAnimation(.snappy(duration: 0.16)) {
                drawPreviewTitle = card.title
            }
            impact.impactOccurred(intensity: index == run.indices.last ? 0.75 : 0.38)
            try? await Task.sleep(for: .milliseconds(index == run.indices.last ? 260 : 120))
        }

        guard !Task.isCancelled, let finalCard = run.last else {
            drawPreviewTitle = nil
            isDrawing = false
            return
        }

        guard !Task.isCancelled else {
            drawPreviewTitle = nil
            isDrawing = false
            return
        }

        withAnimation(.snappy(duration: 0.28)) {
            selectedCardID = finalCard.id
            camera = KakaoMapCamera(latitude: finalCard.latitude, longitude: finalCard.longitude, level: KakaoMapCamera.focusedLevel)
            drawPreviewTitle = nil
            isDrawing = false
        }
        success.notificationOccurred(.success)
    }

    private func drawRun(from pool: [RecommendationCardModel]) -> [RecommendationCardModel] {
        let count = min(max(pool.count, 1), 4)
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

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 5) {
                    Label(card.category, systemImage: card.categoryIconName)
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

            if card.randomSlotKind == .festival, card.hasFestivalDetail {
                FestivalInfoPanel(card: card)
            }

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
        .accessibilityLabel("랜덤 \(card.category) 추천, \(card.title), \(card.district)")
    }
}

private struct FestivalInfoPanel: View {
    let card: RecommendationCardModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let eventPeriodLabel = card.eventPeriodLabel {
                Label(eventPeriodLabel, systemImage: "calendar")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(PeroMapStyle.ink)
            }

            if let eventSummary = card.eventSummary {
                Text(eventSummary)
                    .font(.caption)
                    .foregroundStyle(PeroMapStyle.inkSoft)
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(PeroMapStyle.surfaceMuted, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .accessibilityElement(children: .combine)
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

private extension RecommendationCardModel {
    var hasFestivalDetail: Bool {
        eventPeriodLabel != nil || eventSummary != nil
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

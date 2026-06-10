import SwiftUI
import UIKit
import AudioToolbox
import PeroCore
import KakaoSDKShare
import KakaoSDKTemplate

struct HomeRecommendationScreen: View {
    @ObservedObject var viewModel: RecommendationViewModel
    @State private var pickerMode: RecommendationPickerMode = .restaurant
    @State private var selectedCardID: RecommendationCardModel.ID?
    @State private var rerollTask: Task<Void, Never>?
    @State private var drawTask: Task<Void, Never>?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isDrawing = false
    @State private var isLocating = false
    @State private var drawPhase: DrawPhase = .idle
    @State private var drawPreviewTitle: String?
    @State private var drawCandidateTrail: [RecommendationCardModel] = []
    @State private var drawHighlightedCardIDs: Set<RecommendationCardModel.ID> = []
    @State private var drawRevealedCardID: RecommendationCardModel.ID?
    @State private var diceState = DrawDiceAnimationState()
    @State private var mapImpactOffset: CGSize = .zero
    @State private var mapImpactRotation: Double = 0
    @State private var locationFeedback: String?
    @State private var currentUserCoordinate: UserCoordinate?
    @State private var didCenterOnInitialLocation = false
    @State private var camera = KakaoMapCamera.seoul
    @State private var visibleBounds: KakaoMapVisibleBounds?
    @State private var mapRefreshTask: Task<Void, Never>?
    @State private var lastMapRefreshKey: String?
#if DEBUG
    @State private var didApplyScreenshotScenario = false
    @State private var didBootstrapScreenshotScenario = false
#endif

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
        var markers: [KakaoMapMarker] = []
        if let selectedCard {
            markers.append(
                KakaoMapMarker(
                    id: selectedCard.id,
                    latitude: selectedCard.latitude,
                    longitude: selectedCard.longitude,
                    kind: selectedCard.mapMarkerKind,
                    isSelected: true,
                    isHighlighted: false
                )
            )
        }
        if let currentUserCoordinate {
            markers.append(
                KakaoMapMarker(
                    id: "current-user-location",
                    latitude: currentUserCoordinate.latitude,
                    longitude: currentUserCoordinate.longitude,
                    isSelected: false,
                    isHighlighted: false,
                    isUserLocation: true
                )
            )
        }
        return markers
    }

    private var markerCandidateCards: [RecommendationCardModel] {
        let cards = candidates(for: pickerMode)
        guard let visibleBounds else {
            return Array(cards.prefix(80))
        }
        return cards.filter { visibleBounds.contains(latitude: $0.latitude, longitude: $0.longitude) }
    }

    var body: some View {
        ZStack {
            mapCanvas
            drawExperienceOverlay
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
#if DEBUG
            scheduleScreenshotScenarioIfNeeded()
#endif
        }
        .onChange(of: viewModel.cards) { _, cards in
            reconcileSelection(with: cards)
#if DEBUG
            applyScreenshotScenarioIfNeeded(cards: cards)
#endif
        }
        .onChange(of: viewModel.activeCenterCoordinate) { _, coordinate in
            centerOnInitialLocationIfNeeded(coordinate)
        }
        .onChange(of: pickerMode) { _, _ in
            selectedCardID = nil
            scheduleMapScopedRefresh()
        }
        .onChange(of: visibleBounds) { _, _ in
            guard !isDrawing else { return }
            reconcileSelection(with: viewModel.cards)
            scheduleMapScopedRefresh()
        }
        .onChange(of: camera) { _, _ in
            guard !isDrawing else { return }
            scheduleMapScopedRefresh()
        }
        .onDisappear {
            rerollTask?.cancel()
            drawTask?.cancel()
            mapRefreshTask?.cancel()
        }
    }

    private var mapCanvas: some View {
        GeometryReader { proxy in
            KakaoMapView(camera: $camera, markers: mapMarkers) { bounds in
                visibleBounds = bounds
            }
                .frame(width: proxy.size.width, height: proxy.size.height)
                .offset(mapImpactOffset)
                .rotationEffect(.degrees(mapImpactRotation))
                .scaleEffect(isDrawing && !reduceMotion ? 1.004 : 1)
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
    private var drawExperienceOverlay: some View {
        if isDrawing || drawPhase != .idle {
            DrawExperienceOverlay(
                phase: drawPhase,
                previewTitle: drawPreviewTitle,
                candidateTrail: drawCandidateTrail,
                modeTitle: pickerMode.title,
                diceState: diceState,
                reduceMotion: reduceMotion
            )
            .transition(.opacity.combined(with: .scale(scale: reduceMotion ? 1 : 0.94)))
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
                    Image(systemName: "scope")
                        .font(.system(size: 18, weight: .semibold))
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
        .opacity(isDrawing ? 0.72 : 1)
        .accessibilityElement(children: .contain)
    }

    private var categoryMenuSegment: some View {
        Menu {
            ForEach(RecommendationPickerMode.allCases) { mode in
                Button {
                    pickerMode = mode
                    selectedCardID = nil
                    drawPreviewTitle = nil
                    drawPhase = .idle
                    drawCandidateTrail = []
                } label: {
                    Text(mode.title)
                }
            }
        } label: {
            Text(pickerMode.title)
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
            RangePickButtonLabel(
                title: drawActionTitle,
                phase: drawPhase,
                compact: selectedCard != nil
            )
        }
        .buttonStyle(RangePickButtonStyle(isActive: isDrawing || drawPhase != .idle, reduceMotion: reduceMotion))
        .disabled(isDrawing)
        .accessibilityLabel(randomButtonTitle)
        .accessibilityIdentifier("mapRandomPickButton")
    }

    private var randomButtonTitle: String {
        switch viewModel.state {
        case .loading:
            HomeMapKoreanCopy.rangePickTitle(for: pickerMode.title)
        default:
            if isDrawing {
                drawPhase.accessibilityTitle
            } else {
                HomeMapKoreanCopy.rangePickTitle(for: pickerMode.title)
            }
        }
    }

    private var drawActionTitle: String {
        if isDrawing { return drawPhase.buttonTitle }
        return HomeMapKoreanCopy.rangePickTitle(for: pickerMode.title)
    }

    @ViewBuilder
    private var selectedResultSheet: some View {
        if let selectedCard {
            RandomMapResultSheet(
                card: selectedCard
            )
            .transition(.move(edge: .bottom).combined(with: .opacity))
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


#if DEBUG
    private var screenshotScenario: String? {
        let value = ProcessInfo.processInfo.environment["PERO_SCREENSHOT_SCENARIO"]?.trimmingCharacters(in: .whitespacesAndNewlines)
        return value?.isEmpty == false ? value : nil
    }

    private func scheduleScreenshotScenarioIfNeeded() {
        guard let scenario = screenshotScenario, !didBootstrapScreenshotScenario else { return }
        didBootstrapScreenshotScenario = true
        Task { @MainActor in
            let mode = screenshotMode(for: scenario)
            let camera = screenshotCamera(for: mode)
            let bounds = screenshotBounds(for: mode)
            pickerMode = mode
            selectedCardID = nil
            currentUserCoordinate = UserCoordinate(latitude: camera.latitude, longitude: camera.longitude)
            self.camera = camera
            visibleBounds = bounds
            await viewModel.loadGoNowRecommendations(
                center: UserCoordinate(latitude: camera.latitude, longitude: camera.longitude),
                visibleBounds: bounds,
                camera: camera,
                mode: mode
            )
            applyScreenshotScenarioIfNeeded(cards: viewModel.cards)
        }
    }

    private func applyScreenshotScenarioIfNeeded(cards: [RecommendationCardModel]) {
        guard !didApplyScreenshotScenario, let scenario = screenshotScenario else { return }
        let nextMode = screenshotMode(for: scenario)
        guard let card = screenshotTargetCard(from: cards, mode: nextMode) else { return }
        didApplyScreenshotScenario = true
        pickerMode = nextMode
        selectedCardID = scenario.contains("result") || scenario.contains("lock") ? card.id : nil
        let currentLevel = camera.level
        camera = KakaoMapCamera(latitude: card.latitude, longitude: card.longitude, level: currentLevel)
        if scenario.contains("dice") {
            isDrawing = true
            drawPhase = .shuffling
            drawPreviewTitle = nil
            drawCandidateTrail = Array(cards.filter { nextMode.matches($0) }.prefix(3))
            diceState = DrawDiceAnimationState(
                normalizedPosition: CGPoint(x: 0.78, y: 0.28),
                rotation: 318,
                scale: 1.02,
                blur: 2.0,
                impact: 0.7
            )
            triggerMapImpact(from: diceState.normalizedPosition, intensity: 0.62)
        } else if scenario.contains("lock") {
            isDrawing = true
            drawPhase = .locking
            drawPreviewTitle = card.title
            drawCandidateTrail = [card]
            diceState = DrawDiceAnimationState(
                normalizedPosition: CGPoint(x: 0.52, y: 0.42),
                rotation: 92,
                scale: 1.06,
                blur: 0,
                impact: 0.9
            )
        } else {
            isDrawing = false
            drawPhase = .idle
            drawPreviewTitle = nil
            drawCandidateTrail = []
            diceState = DrawDiceAnimationState()
        }
    }

    private func screenshotMode(for scenario: String) -> RecommendationPickerMode {
        let normalized = scenario.lowercased()
        if normalized.contains("festival") { return .festival }
        if normalized.contains("place") || normalized.contains("attraction") { return .attraction }
        return .restaurant
    }

    private func screenshotTargetCard(
        from cards: [RecommendationCardModel],
        mode: RecommendationPickerMode
    ) -> RecommendationCardModel? {
        let matchingCards = cards.filter { mode.matches($0) }
        if mode == .restaurant {
            return matchingCards.first {
                $0.sourceAttribution == "kakaoLocal"
                && $0.randomSlotKind == .restaurant
                && !$0.category.localizedCaseInsensitiveContains("카페")
                && !$0.title.localizedCaseInsensitiveContains("카페")
            }
        }
        if mode == .festival {
            return matchingCards.first { $0.hasFestivalDetail } ?? matchingCards.first
        }
        return matchingCards.first
    }

    private func screenshotCamera(for mode: RecommendationPickerMode) -> KakaoMapCamera {
        switch mode {
        case .restaurant:
            KakaoMapCamera(latitude: 37.6377, longitude: 127.0650, level: KakaoMapCamera.focusedLevel)
        case .festival:
            KakaoMapCamera(latitude: 37.5665, longitude: 126.9780, level: 8)
        case .attraction:
            KakaoMapCamera(latitude: 37.5665, longitude: 126.9780, level: 10)
        }
    }

    private func screenshotBounds(for mode: RecommendationPickerMode) -> KakaoMapVisibleBounds {
        switch mode {
        case .restaurant:
            KakaoMapVisibleBounds(
                minLatitude: 37.61,
                maxLatitude: 37.66,
                minLongitude: 127.04,
                maxLongitude: 127.09
            )
        case .festival:
            KakaoMapVisibleBounds(
                minLatitude: 37.45,
                maxLatitude: 37.70,
                minLongitude: 126.80,
                maxLongitude: 127.12
            )
        case .attraction:
            KakaoMapVisibleBounds(
                minLatitude: 37.53,
                maxLatitude: 37.60,
                minLongitude: 126.94,
                maxLongitude: 127.02
            )
        }
    }
#endif

    private func rerollRecommendations() {
        rerollTask?.cancel()
        rerollTask = Task {
            if let visibleBounds {
                let center = UserCoordinate(latitude: camera.latitude, longitude: camera.longitude)
                await viewModel.loadGoNowRecommendations(center: center, visibleBounds: visibleBounds, camera: camera, mode: pickerMode)
            } else {
                let center = UserCoordinate(latitude: camera.latitude, longitude: camera.longitude)
                await viewModel.loadGoNowRecommendations(center: center, visibleBounds: nil, camera: camera, mode: pickerMode)
            }
        }
    }

    private func scheduleMapScopedRefresh() {
#if DEBUG
        guard screenshotScenario == nil else { return }
#endif
        guard let visibleBounds else { return }
        let refreshKey = mapRefreshKey(bounds: visibleBounds, camera: camera, mode: pickerMode)
        guard refreshKey != lastMapRefreshKey else { return }
        lastMapRefreshKey = refreshKey
        mapRefreshTask?.cancel()
        mapRefreshTask = Task {
            try? await Task.sleep(for: .milliseconds(450))
            guard !Task.isCancelled else { return }
            let center = UserCoordinate(latitude: camera.latitude, longitude: camera.longitude)
            await viewModel.loadGoNowRecommendations(center: center, visibleBounds: visibleBounds, camera: camera, mode: pickerMode)
        }
    }

    private func mapRefreshKey(
        bounds: KakaoMapVisibleBounds,
        camera: KakaoMapCamera,
        mode: RecommendationPickerMode
    ) -> String {
        [
            mode.rawValue,
            String(format: "%.3f", camera.latitude),
            String(format: "%.3f", camera.longitude),
            String(camera.level),
            String(format: "%.3f", bounds.minLatitude),
            String(format: "%.3f", bounds.maxLatitude),
            String(format: "%.3f", bounds.minLongitude),
            String(format: "%.3f", bounds.maxLongitude)
        ].joined(separator: "|")
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
        await viewModel.loadGoNowRecommendations(center: coordinate, visibleBounds: visibleBounds, camera: camera, mode: pickerMode)
        try? await Task.sleep(for: .milliseconds(800))
        await MainActor.run {
            withAnimation(.snappy(duration: 0.16)) {
                locationFeedback = nil
            }
        }
    }

    private func runMapDrawAnimation() {
        selectedCardID = nil
        drawTask?.cancel()
        drawTask = Task { @MainActor in
            if viewportCandidateCards.isEmpty {
                await refreshCandidatesForDraw()
            }
            guard !Task.isCancelled else { return }
            let pool = viewportCandidateCards
            guard !pool.isEmpty else {
                resetDrawState()
                return
            }
            await animateMapDraw(with: pool)
        }
    }

    @MainActor
    private func refreshCandidatesForDraw() async {
        let center = UserCoordinate(latitude: camera.latitude, longitude: camera.longitude)
        await viewModel.loadGoNowRecommendations(center: center, visibleBounds: visibleBounds, camera: camera, mode: pickerMode)
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
        drawPreviewTitle = nil
        drawCandidateTrail = []
        drawHighlightedCardIDs = []
        drawRevealedCardID = nil
        diceState = DrawDiceAnimationState()
        resetMapImpact()

        let tickImpact = UIImpactFeedbackGenerator(style: .light)
        let lockImpact = UIImpactFeedbackGenerator(style: .medium)
        let success = UINotificationFeedbackGenerator()
        tickImpact.prepare()
        lockImpact.prepare()
        success.prepare()

        let run = drawRun(from: pool)
        guard let finalCard = run.last else {
            resetDrawState()
            return
        }

        withAnimation(.snappy(duration: reduceMotion ? 0.12 : 0.18)) {
            drawPhase = .scanning
            drawPreviewTitle = HomeMapKoreanCopy.drawScanningTitle
            drawHighlightedCardIDs = []
            diceState = DrawDiceAnimationState(
                normalizedPosition: CGPoint(x: 0.50, y: 0.46),
                rotation: -18,
                scale: 0.94,
                blur: 0,
                impact: 0
            )
        }
        playDrawTickSound()
        tickImpact.impactOccurred(intensity: 0.35)
        try? await Task.sleep(for: .milliseconds(reduceMotion ? 120 : 220))

        guard !Task.isCancelled else {
            resetDrawState()
            return
        }

        if reduceMotion {
            withAnimation(.easeInOut(duration: 0.16)) {
                drawPhase = .locking
                drawPreviewTitle = finalCard.title
                drawCandidateTrail = [finalCard]
                diceState.normalizedPosition = targetPoint(for: finalCard)
            }
            try? await Task.sleep(for: .milliseconds(180))
        } else {
            withAnimation(.snappy(duration: 0.12)) {
                drawPhase = .shuffling
            }
            let intervals: [Int] = [56, 48, 44, 50, 58, 66, 74, 84, 98, 116, 140, 176, 230]
            let points = diceBouncePath(target: targetPoint(for: finalCard), count: intervals.count)
            let shuffledRun = expandedDrawRun(from: run, targetCount: intervals.count)
            for (index, card) in shuffledRun.enumerated() {
                guard !Task.isCancelled else {
                    resetDrawState()
                    return
                }
                let point = points[min(index, points.count - 1)]
                let isFinalStep = index == shuffledRun.indices.last
                withAnimation(.interpolatingSpring(stiffness: isFinalStep ? 210 : 360, damping: isFinalStep ? 18 : 12)) {
                    drawPreviewTitle = isFinalStep ? card.title : nil
                    drawCandidateTrail = Array(shuffledRun.prefix(index + 1).suffix(3))
                    drawHighlightedCardIDs = [card.id]
                    diceState = DrawDiceAnimationState(
                        normalizedPosition: point,
                        rotation: Double((index + 1) * 137),
                        scale: isFinalStep ? 1.10 : (index.isMultiple(of: 3) ? 1.03 : 0.96),
                        blur: isFinalStep ? 0 : CGFloat(max(0, 6 - index / 2)),
                        impact: isFinalStep ? 1 : 0.55
                    )
                }
                if isWallBounce(point) || isFinalStep {
                    triggerMapImpact(from: point, intensity: isFinalStep ? 1.15 : 0.72)
                    playDrawTickSound()
                    tickImpact.impactOccurred(intensity: isFinalStep ? 0.8 : 0.42)
                }
                try? await Task.sleep(for: .milliseconds(intervals[min(index, intervals.count - 1)]))
            }
        }

        guard !Task.isCancelled else {
            resetDrawState()
            return
        }

        withAnimation(.spring(response: 0.28, dampingFraction: 0.72)) {
            drawPhase = .locking
            drawPreviewTitle = finalCard.title
            drawCandidateTrail = Array(drawCandidateTrail.suffix(2)) + [finalCard]
            drawHighlightedCardIDs = [finalCard.id]
            diceState.normalizedPosition = targetPoint(for: finalCard)
            diceState.rotation += 92
            diceState.scale = 1.18
            diceState.blur = 0
        }
        triggerMapImpact(from: targetPoint(for: finalCard), intensity: 1.25)
        playDrawRevealSound()
        lockImpact.impactOccurred(intensity: 0.85)
        try? await Task.sleep(for: .milliseconds(reduceMotion ? 120 : 260))

        guard !Task.isCancelled else {
            resetDrawState()
            return
        }

        withAnimation(.snappy(duration: reduceMotion ? 0.16 : 0.28)) {
            selectedCardID = finalCard.id
            drawRevealedCardID = finalCard.id
            drawHighlightedCardIDs = []
            viewModel.recordRecentPick(cardID: finalCard.id)
            camera = KakaoMapCamera(latitude: finalCard.latitude, longitude: finalCard.longitude, level: camera.level)
            drawPhase = .revealed
            diceState.scale = 0.82
            diceState.impact = 0
        }
        playDrawRevealSound()
        success.notificationOccurred(.success)

        try? await Task.sleep(for: .milliseconds(reduceMotion ? 120 : 520))
        withAnimation(.snappy(duration: 0.18)) {
            resetDrawState()
        }
    }

    private func resetDrawState() {
        drawPreviewTitle = nil
        drawCandidateTrail = []
        drawHighlightedCardIDs = []
        drawRevealedCardID = nil
        drawPhase = .idle
        isDrawing = false
        diceState = DrawDiceAnimationState()
        resetMapImpact()
    }

    private func drawRun(from pool: [RecommendationCardModel]) -> [RecommendationCardModel] {
        let count = min(max(pool.count, 1), 5)
        let shuffled = pool.shuffled()
        if shuffled.count <= count {
            return shuffled
        }
        return Array(shuffled.prefix(count))
    }


    private func targetPoint(for card: RecommendationCardModel) -> CGPoint {
        guard let visibleBounds else { return CGPoint(x: 0.50, y: 0.42) }
        let longitudeRange = max(visibleBounds.maxLongitude - visibleBounds.minLongitude, 0.000_001)
        let latitudeRange = max(visibleBounds.maxLatitude - visibleBounds.minLatitude, 0.000_001)
        let x = (card.longitude - visibleBounds.minLongitude) / longitudeRange
        let y = 1 - ((card.latitude - visibleBounds.minLatitude) / latitudeRange)
        return CGPoint(x: min(max(x, 0.12), 0.88), y: min(max(y, 0.14), 0.78))
    }

    private func diceBouncePath(target: CGPoint, count: Int) -> [CGPoint] {
        let wallPoints: [CGPoint] = [
            CGPoint(x: 0.18, y: 0.16),
            CGPoint(x: 0.84, y: 0.22),
            CGPoint(x: 0.76, y: 0.72),
            CGPoint(x: 0.12, y: 0.64),
            CGPoint(x: 0.28, y: 0.28),
            CGPoint(x: 0.88, y: 0.52),
            CGPoint(x: 0.44, y: 0.76),
            CGPoint(x: 0.16, y: 0.34),
            CGPoint(x: 0.72, y: 0.18)
        ].shuffled()
        var path = Array(wallPoints.prefix(max(0, count - 4)))
        path.append(CGPoint(x: (target.x + 0.18) / 2, y: min(0.80, max(0.16, target.y + 0.20))))
        path.append(CGPoint(x: min(0.88, max(0.12, target.x - 0.10)), y: min(0.78, max(0.14, target.y - 0.12))))
        path.append(CGPoint(x: min(0.88, max(0.12, target.x + 0.04)), y: min(0.78, max(0.14, target.y + 0.05))))
        path.append(target)
        return Array(path.prefix(count))
    }

    private func isWallBounce(_ point: CGPoint) -> Bool {
        point.x < 0.20 || point.x > 0.80 || point.y < 0.20 || point.y > 0.68
    }

    private func triggerMapImpact(from point: CGPoint, intensity: CGFloat) {
        let xDirection: CGFloat = point.x < 0.5 ? 1 : -1
        let yDirection: CGFloat = point.y < 0.5 ? 1 : -1
        withAnimation(.interpolatingSpring(stiffness: 520, damping: 18)) {
            mapImpactOffset = CGSize(width: xDirection * 7 * intensity, height: yDirection * 5 * intensity)
            mapImpactRotation = Double(xDirection * 0.32 * intensity)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
            resetMapImpact()
        }
    }

    private func resetMapImpact() {
        withAnimation(.interpolatingSpring(stiffness: 420, damping: 20)) {
            mapImpactOffset = .zero
            mapImpactRotation = 0
        }
    }

    private func playDrawTickSound() {
        AudioServicesPlaySystemSound(1104)
    }

    private func playDrawRevealSound() {
        AudioServicesPlaySystemSound(1025)
    }

    private func expandedDrawRun(from run: [RecommendationCardModel], targetCount: Int) -> [RecommendationCardModel] {
        guard !run.isEmpty else { return [] }
        var expanded: [RecommendationCardModel] = []
        while expanded.count < targetCount {
            expanded.append(contentsOf: run.shuffled())
        }
        expanded = Array(expanded.prefix(targetCount))
        if let finalCard = run.last {
            expanded[expanded.count - 1] = finalCard
        }
        return expanded
    }

}

enum HomeMapKoreanCopy {
    static let readyMessage = "위치를 확인하고 있습니다."
    static let loadingMessage = "가까운 장소를 불러오고 있습니다."
    static let emptyMessage = ""
    static let restaurantEmptyMessage = ""
    static let viewportEmptyMessage = ""
    static let drawScanningTitle = "현재 범위 확인 중"

    static func rangePickTitle(for modeTitle: String) -> String {
        "이 범위에서 \(modeTitle) 뽑기"
    }
}


private enum DrawPhase: Equatable {
    case idle
    case scanning
    case shuffling
    case locking
    case revealed

    var buttonTitle: String {
        switch self {
        case .idle:
            "이 범위에서 뽑기"
        case .scanning:
            "스캔 중"
        case .shuffling:
            "섞는 중"
        case .locking:
            "잠금"
        case .revealed:
            "완료"
        }
    }

    var accessibilityTitle: String {
        switch self {
        case .idle:
            "뽑기 준비"
        case .scanning:
            "지도 범위 확인 중"
        case .shuffling:
            "섞는 중"
        case .locking:
            "결과 확정 중"
        case .revealed:
            "뽑기 완료"
        }
    }

    var overlayTitle: String {
        switch self {
        case .idle:
            "준비"
        case .scanning:
            "스캔 중"
        case .shuffling:
            "섞는 중"
        case .locking:
            "여기로 결정"
        case .revealed:
            "뽑기 완료"
        }
    }

    var systemImage: String {
        switch self {
        case .idle:
            "sparkles"
        case .scanning:
            "scope"
        case .shuffling:
            "shuffle"
        case .locking:
            "mappin.and.ellipse"
        case .revealed:
            "checkmark.seal.fill"
        }
    }
}

private struct RangePickButtonLabel: View {
    let title: String
    let phase: DrawPhase
    let compact: Bool

    var body: some View {
        Text(title)
            .lineLimit(1)
        .font(.subheadline.weight(.semibold))
        .foregroundStyle(PeroMapStyle.ink)
        .padding(.leading, 12)
        .padding(.trailing, 16)
        .frame(height: compact ? 38 : 44)
    }
}

private struct RangePickButtonStyle: ButtonStyle {
    let isActive: Bool
    let reduceMotion: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(alignment: .center) {
                if isActive || configuration.isPressed {
                    Capsule()
                        .fill(PeroMapStyle.accentPale.opacity(configuration.isPressed ? 0.90 : 0.55))
                        .padding(.vertical, 4)
                        .padding(.horizontal, 3)
                }
            }
            .overlay(alignment: .center) {
                if isActive && !reduceMotion {
                    Capsule()
                        .stroke(PeroMapStyle.accentDeep.opacity(0.55), lineWidth: 1.2)
                        .padding(.vertical, 4)
                        .padding(.horizontal, 3)
                        .transition(.opacity)
                }
            }
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.94 : 1)
            .animation(.spring(response: 0.22, dampingFraction: 0.72), value: configuration.isPressed)
            .animation(.snappy(duration: 0.18), value: isActive)
    }
}

private struct DrawDiceAnimationState: Equatable {
    var normalizedPosition: CGPoint = CGPoint(x: 0.50, y: 0.46)
    var rotation: Double = 0
    var scale: CGFloat = 0.92
    var blur: CGFloat = 0
    var impact: CGFloat = 0
}

private struct DrawExperienceOverlay: View {
    let phase: DrawPhase
    let previewTitle: String?
    let candidateTrail: [RecommendationCardModel]
    let modeTitle: String
    let diceState: DrawDiceAnimationState
    let reduceMotion: Bool

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                if !reduceMotion {
                    DiceMotionTrail(diceState: diceState)
                        .allowsHitTesting(false)
                }

                DiceToken(phase: phase, state: diceState, reduceMotion: reduceMotion)
                    .position(
                        x: proxy.size.width * diceState.normalizedPosition.x,
                        y: proxy.size.height * diceState.normalizedPosition.y
                    )

                DrawTickerCard(
                    phase: phase,
                    previewTitle: previewTitle,
                    candidateTrail: candidateTrail,
                    modeTitle: modeTitle,
                    reduceMotion: reduceMotion
                )
                .position(x: proxy.size.width * 0.5, y: proxy.size.height * 0.20)
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityLabel)
    }

    private var accessibilityLabel: String {
        if let previewTitle, !previewTitle.isEmpty {
            "\(phase.accessibilityTitle), \(previewTitle)"
        } else {
            phase.accessibilityTitle
        }
    }
}

private struct DiceMotionTrail: View {
    let diceState: DrawDiceAnimationState

    var body: some View {
        GeometryReader { proxy in
            ForEach(0..<4, id: \.self) { index in
                Image("pero-dice-marker")
                    .resizable()
                    .scaledToFit()
                    .opacity(0.18 - Double(index) * 0.032)
                    .frame(width: 48, height: 48)
                    .rotationEffect(.degrees(diceState.rotation - Double(index * 18)))
                    .position(
                        x: proxy.size.width * diceState.normalizedPosition.x - CGFloat(index * 13),
                        y: proxy.size.height * diceState.normalizedPosition.y + CGFloat(index * 8)
                    )
                    .blur(radius: CGFloat(index) + diceState.blur * 0.42)
            }
        }
    }
}

private struct DiceToken: View {
    let phase: DrawPhase
    let state: DrawDiceAnimationState
    let reduceMotion: Bool

    var body: some View {
        Image("pero-dice-marker")
            .resizable()
            .scaledToFit()
            .frame(width: 56, height: 56)
            .shadow(color: .black.opacity(0.22), radius: 14 + state.impact * 6, y: 8)
        .scaleEffect(state.scale)
        .rotationEffect(.degrees(reduceMotion ? 0 : state.rotation))
        .blur(radius: reduceMotion ? 0 : state.blur)
        .overlay {
            if phase == .locking || phase == .revealed {
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .stroke(PeroMapStyle.accentDeep.opacity(0.34), lineWidth: 8)
                    .frame(width: 78, height: 78)
                    .scaleEffect(phase == .revealed ? 1.22 : 0.96)
                    .opacity(phase == .revealed ? 0.0 : 1.0)
            }
        }
        .animation(.spring(response: 0.24, dampingFraction: 0.68), value: phase)
    }
}

private struct DrawTickerCard: View {
    let phase: DrawPhase
    let previewTitle: String?
    let candidateTrail: [RecommendationCardModel]
    let modeTitle: String
    let reduceMotion: Bool

    var body: some View {
        VStack(spacing: 8) {
            Text(phase.overlayTitle)
                .font(.caption.weight(.bold))
                .foregroundStyle(PeroMapStyle.muted)

            Text(displayTitle)
                .font(.headline.weight(.bold))
                .foregroundStyle(PeroMapStyle.ink)
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .id(displayTitle)
                .transition(.opacity.combined(with: .scale(scale: reduceMotion ? 1 : 0.95)))

            if !candidateTrail.isEmpty && !reduceMotion {
                HStack(spacing: 4) {
                    ForEach(candidateTrail.suffix(3)) { card in
                        Text(card.category.prefix(3))
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(PeroMapStyle.inkSoft)
                            .lineLimit(1)
                            .padding(.horizontal, 8)
                            .frame(height: 24)
                            .background(PeroMapStyle.accentPale, in: Capsule())
                    }
                }
                .transition(.opacity)
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
        .frame(maxWidth: 286)
        .background {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(Color.white.opacity(0.84))
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                .overlay(alignment: .topLeading) {
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [Color.white.opacity(0.55), Color.white.opacity(0.08)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .blendMode(.plusLighter)
                }
        }
        .overlay {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(phase == .locking ? PeroMapStyle.accentDeep.opacity(0.70) : Color.white.opacity(0.76), lineWidth: phase == .locking ? 1.8 : 1.0)
        }
        .shadow(color: .black.opacity(0.08), radius: 18, y: 8)
        .animation(.spring(response: 0.26, dampingFraction: 0.76), value: phase)
    }

    private var displayTitle: String {
        if let previewTitle, !previewTitle.isEmpty {
            return previewTitle
        }
        return "\(modeTitle) 뽑는 중"
    }
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
                PeroBrandLogoMark(size: 46)
            }

            FlowMetadataRow(card: card)

            if card.randomSlotKind == .festival, card.hasFestivalDetail {
                FestivalInfoPanel(card: card)
            }

            HStack(spacing: 10) {
                KakaoTalkShareButton(card: card)
                    .buttonStyle(PeroActionButtonStyle())

                KakaoDirectionsButton(card: card)
                    .buttonStyle(PeroActionButtonStyle())

                NavigationLink(value: AppRoute.recommendationDetail(cardID: card.id)) {
                    Label("상세", systemImage: "info.circle")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(PeroActionButtonStyle())
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


private struct KakaoTalkShareButton: View {
    let card: RecommendationCardModel
    @State private var shareErrorMessage: String?

    var body: some View {
        Button(action: shareToKakaoTalk) {
            Label("카톡", systemImage: "message.fill")
                .frame(maxWidth: .infinity)
        }
        .alert("카카오톡 공유 실패", isPresented: Binding(
            get: { shareErrorMessage != nil },
            set: { if !$0 { shareErrorMessage = nil } }
        )) {
            Button("확인", role: .cancel) { shareErrorMessage = nil }
        } message: {
            Text(shareErrorMessage ?? "")
        }
    }

    private func shareToKakaoTalk() {
        guard ShareApi.isKakaoTalkSharingAvailable() else {
            shareErrorMessage = "이 기기에 카카오톡이 설치되어 있지 않습니다."
            return
        }

        let shareImage = card.makeKakaoShareCardImage()
        ShareApi.shared.imageUpload(image: shareImage, secureResource: true) { result, _ in
            DispatchQueue.main.async {
                share(templateImageURL: result?.infos.original.url ?? card.kakaoShareImageURL)
            }
        }
    }

    private func share(templateImageURL: URL?) {
        let template = makeTemplate(imageURL: templateImageURL)
        ShareApi.shared.shareDefault(templatable: template, shareType: .default, limit: 5) { sharingResult, error in
            DispatchQueue.main.async {
                if let error {
                    shareErrorMessage = error.localizedDescription
                    return
                }
                guard let url = sharingResult?.url else {
                    shareErrorMessage = "공유 링크를 만들지 못했습니다."
                    return
                }
                UIApplication.shared.open(url)
            }
        }
    }

    private func makeTemplate(imageURL: URL?) -> FeedTemplate {
        let kakaoMapURL = card.kakaoMapMobileWebURL
        let peroLink = Link(
            webUrl: kakaoMapURL,
            mobileWebUrl: kakaoMapURL,
            iosExecutionParams: ["placeId": card.id]
        )
        let kakaoMapLink = Link(webUrl: kakaoMapURL, mobileWebUrl: kakaoMapURL)
        return FeedTemplate(
            content: Content(
                title: card.kakaoShareTitle,
                imageUrl: imageURL,
                imageWidth: 1024,
                imageHeight: 1024,
                description: card.kakaoShareDescription,
                link: peroLink
            ),
            buttons: [
                Button(title: "카카오맵 길찾기", link: kakaoMapLink)
            ]
        )
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

            if let officialURL = card.officialURL {
                Link(destination: officialURL) {
                    Label("공식 사이트", systemImage: "safari")
                        .font(.caption.weight(.bold))
                }
                .foregroundStyle(PeroMapStyle.ink)
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
        eventPeriodLabel != nil || eventSummary != nil || officialURL != nil
    }

    var kakaoShareTitle: String { title }

    var kakaoShareDescription: String? { nil }

    func makeKakaoShareCardImage() -> UIImage {
        PeroShareCardRenderer.render(placeName: title, logo: UIImage(named: "pero-brand-logo"))
    }

    var kakaoMapMobileWebURL: URL {
        if let placeID = kakaoPlaceID {
            return URL(string: "https://m.map.kakao.com/scheme/place?id=\(placeID)")!
        }
        return kakaoMapDirectionsWebURL
    }

    var kakaoShareImageURL: URL? {
        guard
            let baseURLString = Bundle.main.object(forInfoDictionaryKey: "PERO_API_BASE_URL") as? String,
            let baseURL = URL(string: baseURLString)
        else { return nil }
        return baseURL.appendingPathComponent("assets/share/pero-random.png")
    }

    private var kakaoPlaceID: String? {
        guard id.hasPrefix("kakao-") else { return nil }
        let placeID = String(id.dropFirst("kakao-".count))
        return placeID.isEmpty ? nil : placeID
    }
}


private enum PeroShareCardRenderer {
    static func render(placeName: String, logo: UIImage?) -> UIImage {
        let size = CGSize(width: 1200, height: 680)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        let renderer = UIGraphicsImageRenderer(size: size, format: format)
        return renderer.image { context in
            let cg = context.cgContext
            UIColor(red: 0.969, green: 0.965, blue: 0.949, alpha: 1).setFill()
            cg.fill(CGRect(origin: .zero, size: size))

            let cardRect = CGRect(x: 58, y: 54, width: size.width - 116, height: size.height - 108)
            let cardPath = UIBezierPath(roundedRect: cardRect, cornerRadius: 54)
            UIColor(red: 1.0, green: 0.996, blue: 0.98, alpha: 1).setFill()
            cardPath.fill()
            UIColor(red: 0.871, green: 0.875, blue: 0.863, alpha: 1).setStroke()
            cardPath.lineWidth = 3
            cardPath.stroke()

            drawCelebration(in: cardRect, context: cg)

            if let logo = logo?.croppedNearWhiteBorder() {
                drawAspectFit(image: logo, in: CGRect(x: 390, y: 82, width: 420, height: 128))
            }

            let title = placeName.trimmingCharacters(in: .whitespacesAndNewlines)
            let paragraph = NSMutableParagraphStyle()
            paragraph.alignment = .center
            paragraph.lineBreakMode = .byWordWrapping
            let font = bestFont(for: title, maxWidth: 880, maxLines: 2)
            let attributes: [NSAttributedString.Key: Any] = [
                .font: font,
                .foregroundColor: UIColor(red: 0.090, green: 0.102, blue: 0.114, alpha: 1),
                .paragraphStyle: paragraph,
                .kern: -1.2
            ]
            let nameRect = CGRect(x: 150, y: 268, width: 900, height: 230)
            title.draw(with: nameRect, options: [.usesLineFragmentOrigin, .usesFontLeading], attributes: attributes, context: nil)

            let bottomRect = CGRect(x: 492, y: 544, width: 216, height: 8)
            UIColor(red: 0.608, green: 0.718, blue: 0.831, alpha: 1).setFill()
            UIBezierPath(roundedRect: bottomRect, cornerRadius: 4).fill()
        }
    }

    private static func drawCelebration(in rect: CGRect, context cg: CGContext) {
        cg.saveGState()
        cg.setLineCap(.round)
        cg.setStrokeColor(UIColor(red: 0.090, green: 0.102, blue: 0.114, alpha: 1).cgColor)
        cg.setLineWidth(5)
        let center = CGPoint(x: rect.midX, y: rect.minY + 102)
        let rays: [(CGFloat, CGFloat, CGFloat)] = [
            (-120, -58, 56), (-74, -88, 62), (0, -102, 66), (74, -88, 62), (120, -58, 56),
            (-172, 2, 46), (172, 2, 46)
        ]
        for ray in rays {
            let start = CGPoint(x: center.x + ray.0 * 0.58, y: center.y + ray.1 * 0.58)
            let end = CGPoint(x: center.x + ray.0, y: center.y + ray.1)
            cg.move(to: start)
            cg.addLine(to: end)
            cg.strokePath()
        }

        cg.setStrokeColor(UIColor(red: 0.435, green: 0.573, blue: 0.706, alpha: 1).cgColor)
        cg.setLineWidth(4)
        let arcs = [
            CGRect(x: rect.midX - 336, y: rect.maxY - 132, width: 260, height: 86),
            CGRect(x: rect.midX + 76, y: rect.maxY - 132, width: 260, height: 86)
        ]
        for arc in arcs {
            cg.addArc(center: CGPoint(x: arc.midX, y: arc.midY), radius: arc.width / 2, startAngle: .pi * 0.18, endAngle: .pi * 0.82, clockwise: false)
            cg.strokePath()
        }

        let sparkleColor = UIColor(red: 0.435, green: 0.573, blue: 0.706, alpha: 1)
        drawSparkle(center: CGPoint(x: rect.midX, y: rect.maxY - 84), radius: 29, color: sparkleColor)
        drawSparkle(center: CGPoint(x: rect.minX + 168, y: rect.minY + 170), radius: 19, color: sparkleColor.withAlphaComponent(0.72))
        drawSparkle(center: CGPoint(x: rect.maxX - 176, y: rect.minY + 178), radius: 19, color: sparkleColor.withAlphaComponent(0.72))
        cg.restoreGState()
    }

    private static func drawSparkle(center: CGPoint, radius: CGFloat, color: UIColor) {
        let path = UIBezierPath()
        path.move(to: CGPoint(x: center.x, y: center.y - radius))
        path.addQuadCurve(to: CGPoint(x: center.x + radius, y: center.y), controlPoint: CGPoint(x: center.x + radius * 0.28, y: center.y - radius * 0.28))
        path.addQuadCurve(to: CGPoint(x: center.x, y: center.y + radius), controlPoint: CGPoint(x: center.x + radius * 0.28, y: center.y + radius * 0.28))
        path.addQuadCurve(to: CGPoint(x: center.x - radius, y: center.y), controlPoint: CGPoint(x: center.x - radius * 0.28, y: center.y + radius * 0.28))
        path.addQuadCurve(to: CGPoint(x: center.x, y: center.y - radius), controlPoint: CGPoint(x: center.x - radius * 0.28, y: center.y - radius * 0.28))
        color.setFill()
        path.fill()
    }

    private static func bestFont(for text: String, maxWidth: CGFloat, maxLines: Int) -> UIFont {
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        for size in stride(from: CGFloat(92), through: CGFloat(54), by: CGFloat(-2)) {
            let font = UIFont.systemFont(ofSize: size, weight: .heavy)
            let rect = (text as NSString).boundingRect(
                with: CGSize(width: maxWidth, height: .greatestFiniteMagnitude),
                options: [.usesLineFragmentOrigin, .usesFontLeading],
                attributes: [.font: font, .paragraphStyle: paragraph],
                context: nil
            )
            if rect.height <= font.lineHeight * CGFloat(maxLines) + 12 {
                return font
            }
        }
        return UIFont.systemFont(ofSize: 54, weight: .heavy)
    }

    private static func drawAspectFit(image: UIImage, in rect: CGRect) {
        let scale = min(rect.width / image.size.width, rect.height / image.size.height)
        let drawSize = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        let drawRect = CGRect(
            x: rect.midX - drawSize.width / 2,
            y: rect.midY - drawSize.height / 2,
            width: drawSize.width,
            height: drawSize.height
        )
        image.draw(in: drawRect)
    }
}

private extension UIImage {
    func croppedNearWhiteBorder() -> UIImage {
        guard let cgImage else { return self }
        let width = cgImage.width
        let height = cgImage.height
        guard let dataProvider = cgImage.dataProvider, let data = dataProvider.data else { return self }
        let bytes = CFDataGetBytePtr(data)
        let bytesPerPixel = cgImage.bitsPerPixel / 8
        let bytesPerRow = cgImage.bytesPerRow
        guard bytesPerPixel >= 3 else { return self }

        var minX = width
        var minY = height
        var maxX = 0
        var maxY = 0
        let threshold = 238
        let step = max(1, min(width, height) / 320)
        for y in stride(from: 0, to: height, by: step) {
            for x in stride(from: 0, to: width, by: step) {
                let offset = y * bytesPerRow + x * bytesPerPixel
                let r = Int(bytes![offset])
                let g = Int(bytes![offset + 1])
                let b = Int(bytes![offset + 2])
                if r < threshold || g < threshold || b < threshold {
                    minX = min(minX, x)
                    minY = min(minY, y)
                    maxX = max(maxX, x)
                    maxY = max(maxY, y)
                }
            }
        }
        guard minX < maxX, minY < maxY else { return self }
        let padding = 14
        let crop = CGRect(
            x: max(0, minX - padding),
            y: max(0, minY - padding),
            width: min(width - max(0, minX - padding), maxX - minX + padding * 2),
            height: min(height - max(0, minY - padding), maxY - minY + padding * 2)
        )
        guard let cropped = cgImage.cropping(to: crop) else { return self }
        return UIImage(cgImage: cropped, scale: scale, orientation: imageOrientation)
    }
}

private extension String {
    var trimmedForURLQuery: String {
        trimmingCharacters(in: .whitespacesAndNewlines)
            .addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? self
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

#Preview {
    NavigationStack {
        HomeRecommendationScreen(viewModel: RecommendationViewModel(provider: PeroAPIProviderFactory.preview(), locationProvider: StaticLocationProvider.preview))
    }
}

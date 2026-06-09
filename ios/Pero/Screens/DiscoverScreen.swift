import SwiftUI
import UIKit
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
    @State private var locationFeedback: String?
    @State private var currentUserCoordinate: UserCoordinate?
    @State private var didCenterOnInitialLocation = false
    @State private var camera = KakaoMapCamera.seoul
    @State private var visibleBounds: KakaoMapVisibleBounds?
    @State private var mapRefreshTask: Task<Void, Never>?
    @State private var lastMapRefreshKey: String?

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
        }
        .onChange(of: viewModel.cards) { _, cards in
            reconcileSelection(with: cards)
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
            "찾는 중"
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
        } else if viewModel.state != .results && viewModel.state != .empty {
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

        withAnimation(.snappy(duration: reduceMotion ? 0.12 : 0.22)) {
            drawPhase = .scanning
            drawPreviewTitle = HomeMapKoreanCopy.drawScanningTitle
            drawHighlightedCardIDs = []
        }
        tickImpact.impactOccurred(intensity: 0.35)
        try? await Task.sleep(for: .milliseconds(reduceMotion ? 120 : 330))
        if !reduceMotion {
            withAnimation(.snappy(duration: 0.18)) {
                drawHighlightedCardIDs = []
            }
            try? await Task.sleep(for: .milliseconds(190))
        }

        guard !Task.isCancelled else {
            resetDrawState()
            return
        }

        if reduceMotion {
            withAnimation(.easeInOut(duration: 0.16)) {
                drawPhase = .locking
                drawPreviewTitle = finalCard.title
                drawCandidateTrail = [finalCard]
            }
            try? await Task.sleep(for: .milliseconds(180))
        } else {
            withAnimation(.snappy(duration: 0.16)) {
                drawPhase = .shuffling
            }
            let intervals: [Int] = [54, 58, 64, 72, 84, 98, 116, 138, 166, 202, 246, 304]
            let shuffledRun = expandedDrawRun(from: run, targetCount: intervals.count)
            for (index, card) in shuffledRun.enumerated() {
                guard !Task.isCancelled else {
                    resetDrawState()
                    return
                }
                withAnimation(.snappy(duration: 0.13)) {
                    drawPreviewTitle = card.title
                    drawCandidateTrail = Array(shuffledRun.prefix(index + 1).suffix(3))
                    drawHighlightedCardIDs = [card.id]
                }
                if index % 2 == 0 || index == shuffledRun.indices.last {
                    tickImpact.impactOccurred(intensity: index == shuffledRun.indices.last ? 0.7 : 0.36)
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
        }
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
            camera = KakaoMapCamera(latitude: finalCard.latitude, longitude: finalCard.longitude, level: KakaoMapCamera.focusedLevel)
            drawPhase = .revealed
        }
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
    }

    private func drawRun(from pool: [RecommendationCardModel]) -> [RecommendationCardModel] {
        let count = min(max(pool.count, 1), 5)
        let shuffled = pool.shuffled()
        if shuffled.count <= count {
            return shuffled
        }
        return Array(shuffled.prefix(count))
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
            "뽑기 결과를 확인하세요."
        case .empty:
            pickerMode == .restaurant ? HomeMapKoreanCopy.restaurantEmptyMessage : HomeMapKoreanCopy.emptyMessage
        case .error(let message):
            message
        }
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

private struct DrawExperienceOverlay: View {
    let phase: DrawPhase
    let previewTitle: String?
    let candidateTrail: [RecommendationCardModel]
    let modeTitle: String
    let reduceMotion: Bool

    var body: some View {
        ZStack {
            if !reduceMotion {
                DrawRadarPulse(phase: phase)
                    .allowsHitTesting(false)
            }
            DrawTickerCard(
                phase: phase,
                previewTitle: previewTitle,
                candidateTrail: candidateTrail,
                modeTitle: modeTitle,
                reduceMotion: reduceMotion
            )
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

private struct DrawRadarPulse: View {
    let phase: DrawPhase

    var body: some View {
        TimelineView(.animation) { timeline in
            let base = timeline.date.timeIntervalSinceReferenceDate
            ZStack {
                ForEach(0..<3, id: \.self) { index in
                    let progress = (base * 0.82 + Double(index) * 0.34).truncatingRemainder(dividingBy: 1)
                    Circle()
                        .stroke(PeroMapStyle.accentDeep.opacity(opacity(for: progress)), lineWidth: 2)
                        .frame(width: 116 + CGFloat(progress) * 190, height: 116 + CGFloat(progress) * 190)
                        .scaleEffect(phase == .locking ? 0.76 : 1)
                }
                Circle()
                    .fill(PeroMapStyle.accent.opacity(0.12))
                    .frame(width: phase == .locking ? 86 : 72, height: phase == .locking ? 86 : 72)
                Image(systemName: phase == .locking ? "mappin.and.ellipse" : "scope")
                    .font(.system(size: 28, weight: .bold))
                    .foregroundStyle(PeroMapStyle.accentDeep)
            }
            .animation(.snappy(duration: 0.22), value: phase)
        }
    }

    private func opacity(for progress: Double) -> Double {
        max(0.04, 0.32 * (1 - progress))
    }
}

private struct DrawTickerCard: View {
    let phase: DrawPhase
    let previewTitle: String?
    let candidateTrail: [RecommendationCardModel]
    let modeTitle: String
    let reduceMotion: Bool

    var body: some View {
        VStack(spacing: 10) {
            Label(phase.overlayTitle, systemImage: phase.systemImage)
                .font(.caption.weight(.bold))
                .foregroundStyle(PeroMapStyle.muted)

            Text(displayTitle)
                .font(.title3.weight(.bold))
                .foregroundStyle(PeroMapStyle.ink)
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .id(displayTitle)
                .transition(.opacity.combined(with: .scale(scale: reduceMotion ? 1 : 0.95)))

            if !candidateTrail.isEmpty && !reduceMotion {
                HStack(spacing: -7) {
                    ForEach(candidateTrail.suffix(3)) { card in
                        Text(card.category.prefix(2))
                            .font(.caption2.weight(.black))
                            .foregroundStyle(PeroMapStyle.inkSoft)
                            .frame(width: 34, height: 34)
                            .background(PeroMapStyle.accentPale, in: Circle())
                            .overlay { Circle().stroke(PeroMapStyle.surface, lineWidth: 2) }
                            .shadow(color: PeroMapStyle.ink.opacity(0.08), radius: 5, y: 2)
                    }
                }
                .transition(.opacity.combined(with: .scale(scale: 0.9)))
            }
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 18)
        .frame(maxWidth: 286)
        .background(PeroMapStyle.surface, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(phase == .locking ? PeroMapStyle.accentDeep : PeroMapStyle.accent, lineWidth: phase == .locking ? 2 : 1.4)
        }
        .shadow(color: .black.opacity(0.15), radius: 20, y: 9)
        .scaleEffect(phase == .locking && !reduceMotion ? 1.04 : 1)
        .animation(.spring(response: 0.26, dampingFraction: 0.76), value: phase)
    }

    private var displayTitle: String {
        if let previewTitle, !previewTitle.isEmpty {
            return previewTitle
        }
        return "\(modeTitle) 확인 중"
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
            }

            FlowMetadataRow(card: card)

            if card.randomSlotKind == .festival, card.hasFestivalDetail {
                FestivalInfoPanel(card: card)
            }

            HStack(spacing: 10) {
                KakaoTalkShareButton(card: card)
                    .buttonStyle(.bordered)

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
        let kakaoMapURL = card.kakaoMapMobileWebURL
        let peroLink = Link(
            webUrl: kakaoMapURL,
            mobileWebUrl: kakaoMapURL,
            iosExecutionParams: ["placeId": card.id]
        )
        let kakaoMapLink = Link(webUrl: kakaoMapURL, mobileWebUrl: kakaoMapURL)
        let template = FeedTemplate(
            content: Content(
                title: card.kakaoShareTitle,
                imageUrl: card.kakaoShareImageURL,
                imageWidth: 800,
                imageHeight: 400,
                description: card.kakaoShareDescription,
                link: peroLink
            ),
            itemContent: ItemContent(
                profileText: "Pero 랜덤 뽑기",
                titleImageText: card.kakaoShareBadge,
                titleImageCategory: card.category,
                items: card.kakaoShareItems,
                sum: "카카오맵에서 바로 보기"
            ),
            social: Social(sharedCount: 1),
            buttons: [
                Button(title: "카카오맵에서 보기", link: kakaoMapLink),
                Button(title: "Pero에서 다시 뽑기", link: peroLink)
            ]
        )

        guard ShareApi.isKakaoTalkSharingAvailable() else {
            shareErrorMessage = "이 기기에 카카오톡이 설치되어 있지 않습니다."
            return
        }

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
                .foregroundStyle(PeroMapStyle.accentDeep)
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

    var kakaoShareTitle: String {
        "Pero가 랜덤으로 뽑은 곳"
    }

    var kakaoShareBadge: String {
        switch randomSlotKind {
        case .restaurant:
            "오늘의 식당"
        case .festival:
            "지금 갈 축제"
        case .attraction:
            "근처 장소"
        }
    }

    var kakaoShareDescription: String {
        let placeLine = "\(title) · \(category)"
        let addressLine = !roadAddress.isEmpty ? roadAddress : district
        if addressLine.isEmpty {
            return placeLine
        }
        return "\(placeLine)\n\(addressLine)"
    }

    var kakaoShareItems: [ItemInfo] {
        var items = [
            ItemInfo(item: "뽑기 결과", itemOp: title),
            ItemInfo(item: "카테고리", itemOp: category)
        ]
        let address = !roadAddress.isEmpty ? roadAddress : district
        if !address.isEmpty {
            items.append(ItemInfo(item: "위치", itemOp: address))
        }
        if sourceAttribution == "kakaoLocal" || id.hasPrefix("kakao-") {
            items.append(ItemInfo(item: "출처", itemOp: "카카오 로컬 캐시"))
        }
        return Array(items.prefix(4))
    }

    var kakaoMapMobileWebURL: URL {
        if let placeID = kakaoPlaceID {
            return URL(string: "https://m.map.kakao.com/scheme/place?id=\(placeID)")!
        }
        let query = "\(title) \(roadAddress.isEmpty ? district : roadAddress)".trimmedForURLQuery
        return URL(string: "https://m.map.kakao.com/scheme/search?q=\(query)&p=\(latitude),\(longitude)")!
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

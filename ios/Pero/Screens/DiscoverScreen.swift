import SwiftUI
import MapKit
import PeroCore

struct HomeRecommendationScreen: View {
    @ObservedObject var viewModel: RecommendationViewModel
    @State private var rerollTask: Task<Void, Never>?

    var body: some View {
        ZStack {
            recommendationBackdrop
            recommendationGlassContainer {
                recommendationList
            }
        }
        .refreshable {
            await viewModel.loadGoNowRecommendations()
        }
        .animation(.default, value: viewModel.state)
        .onDisappear {
            rerollTask?.cancel()
        }
    }

    private var recommendationBackdrop: some View {
        LinearGradient(
            colors: [
                Color.blue.opacity(0.20),
                Color.cyan.opacity(0.12),
                Color(.systemGroupedBackground)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .ignoresSafeArea()
    }

    private var recommendationList: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 18) {
                heroSection
                randomSlotSection
                stateSection
            }
            .padding(.horizontal, 20)
            .padding(.top, 24)
            .padding(.bottom, 36)
        }
        .scrollIndicators(.hidden)
    }

    @ViewBuilder
    private func recommendationGlassContainer<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        if #available(iOS 26, *) {
            GlassEffectContainer(spacing: 18) {
                content()
            }
        } else {
            content()
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
        .padding(20)
        .homeRecommendationGlass(cornerRadius: 28, tint: .blue.opacity(0.14))
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
            .font(.caption.weight(.bold))
            .foregroundStyle(.primary)
            .padding(10)
            .background(.ultraThinMaterial, in: Capsule(style: .continuous))
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
                Image(systemName: slot.systemImage)
                    .font(.title2.weight(.bold))
                    .foregroundStyle(slot.tint)
                    .frame(width: 46, height: 46)
                    .homeRecommendationGlass(cornerRadius: 18, tint: slot.tint.opacity(0.14))

                VStack(alignment: .leading, spacing: 5) {
                    Text(slot.title)
                        .font(.headline)
                    Text("“\(slot.userPrompt)”")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }

            if let card {
                MapPreviewCard(card: card)
                    .frame(height: 170)
                    .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))

                RecommendationCardRow(card: card)

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
        .homeRecommendationGlass(cornerRadius: 26, tint: slot.tint.opacity(0.12), interactive: card != nil)
    }
}

private struct RecommendationCardRow: View {
    let card: RecommendationCardModel

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(card.subtitle)
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.blue)
                    Text(card.title)
                        .font(.headline)
                }
                Spacer(minLength: 12)
                Text(card.distanceLabel)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.blue)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(.blue.opacity(0.10), in: Capsule())
            }
            Text(card.reason)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            FlowMetadataRow(card: card)
        }
        .accessibilityElement(children: .combine)
    }
}

private struct FlowMetadataRow: View {
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

private struct SectionTitle: View {
    let title: String

    init(_ title: String) {
        self.title = title
    }

    var body: some View {
        Text(title)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 4)
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
        }
        .padding(16)
        .homeRecommendationGlass(cornerRadius: 20, tint: .white.opacity(0.18))
    }
}


private extension Collection {
    subscript(safe index: Index) -> Element? {
        indices.contains(index) ? self[index] : nil
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
            self
                .background(.background, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .stroke(.quaternary, lineWidth: 1)
                }
        }
    }
}

#Preview {
    NavigationStack {
        HomeRecommendationScreen(viewModel: RecommendationViewModel(provider: PeroAPIProviderFactory.preview(), locationProvider: StaticLocationProvider.preview))
    }
}

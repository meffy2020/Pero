import SwiftUI
import MapKit
import PeroCore

struct HomeRecommendationScreen: View {
    @ObservedObject var viewModel: RecommendationViewModel
    @State private var selectedTheme = DiscoveryTheme.all.first?.id ?? "walk"

    private var selectedThemeModel: DiscoveryTheme {
        DiscoveryTheme.all.first { $0.id == selectedTheme } ?? DiscoveryTheme.all[0]
    }

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
        .animation(.snappy, value: selectedTheme)
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
                themeSelector
                mapFirstEntry
                stateSection
                recommendationSection
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
        VStack(alignment: .leading, spacing: 14) {
            Label(viewModel.locationLabel, systemImage: "location.fill")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.blue)
                .lineLimit(1)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .homeRecommendationGlass(cornerRadius: 16, tint: .cyan.opacity(0.24))
            Text("지금 바로 갈 만한 장소")
                .font(.title2.weight(.bold))
            Text("지도에서 먼저 감을 잡고, 각 카드에서 왜 지금 맞는지 바로 확인해요.")
                .foregroundStyle(.secondary)
            if viewModel.fallbackUsed {
                Label("추천 반경을 넓혀 보완한 결과입니다", systemImage: "info.circle")
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

    private var themeSelector: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionTitle("오늘의 발견 테마")
            ScrollView(.horizontal) {
                LazyHStack(spacing: 10) {
                    ForEach(DiscoveryTheme.all) { theme in
                        Button {
                            selectedTheme = theme.id
                        } label: {
                            ThemePill(theme: theme, isSelected: selectedTheme == theme.id)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 4)
                .padding(.vertical, 2)
            }
            .scrollIndicators(.hidden)
            Text("선택한 테마는 현재 화면의 탐색 맥락만 바꾸는 시각적 진입점입니다.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 4)
        }
    }

    private var mapFirstEntry: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: selectedThemeModel.symbol)
                    .font(.title3.weight(.bold))
                    .foregroundStyle(.blue)
                    .frame(width: 42, height: 42)
                    .homeRecommendationGlass(cornerRadius: 16, tint: .blue.opacity(0.12))
                VStack(alignment: .leading, spacing: 4) {
                    Text("지도에서 먼저 둘러보기")
                        .font(.headline)
                    Text(selectedThemeModel.prompt)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }

            MapPreviewCard(card: viewModel.cards.first)
                .frame(height: 210)
                .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))

            if let firstCard = viewModel.cards.first {
                HStack(spacing: 10) {
                    NavigationLink(value: AppRoute.mapFocus(cardID: firstCard.id)) {
                        Label("지도에서 확인", systemImage: "map.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)

                    NavigationLink(value: AppRoute.recommendationDetail(cardID: firstCard.id)) {
                        Label("추천 이유 보기", systemImage: "sparkles")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                }
            } else {
                Label("추천 후보를 불러오면 지도 진입이 활성화됩니다", systemImage: "clock")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 9)
                    .homeRecommendationGlass(cornerRadius: 14, tint: .white.opacity(0.18))
            }
        }
        .padding(16)
        .homeRecommendationGlass(cornerRadius: 28, tint: .white.opacity(0.16))
    }

    @ViewBuilder
    private var stateSection: some View {
        switch viewModel.state {
        case .ready:
            StateMessageView(icon: "location", title: "위치 확인 대기", message: "시연용 기본 위치로 추천을 준비합니다.")
        case .loading:
            VStack(alignment: .leading, spacing: 10) {
                SectionTitle("지금 갈 곳 찾는 중")
                HStack(spacing: 12) {
                    ProgressView()
                    Text("장소 메타데이터와 추천 이유를 정리하고 있습니다.")
                        .foregroundStyle(.secondary)
                }
                .padding(16)
                .homeRecommendationGlass(cornerRadius: 20, tint: .white.opacity(0.18))
            }
        case .results:
            EmptyView()
        case .empty:
            StateMessageView(icon: "tray", title: "추천 후보 없음", message: "반경을 넓히거나 백엔드 추천 데이터를 확인해 주세요.")
        case .error(let message):
            StateMessageView(icon: "exclamationmark.triangle", title: "연결 확인 필요", message: message)
        }
    }

    private var recommendationSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionTitle(viewModel.state.title)
            ForEach(viewModel.cards) { card in
                RecommendationCard(card: card)
            }
        }
    }
}

private struct DiscoveryTheme: Identifiable, Equatable {
    let id: String
    let title: String
    let symbol: String
    let prompt: String

    static let all = [
        DiscoveryTheme(id: "walk", title: "산책", symbol: "figure.walk", prompt: "가볍게 움직이기 좋은 주변 장소부터 보여드릴게요."),
        DiscoveryTheme(id: "culture", title: "문화", symbol: "theatermasks", prompt: "전시, 공연, 동네 문화 공간을 발견하는 흐름입니다."),
        DiscoveryTheme(id: "event", title: "행사", symbol: "calendar.badge.clock", prompt: "오늘 들러볼 만한 지역 이벤트 감각으로 정리했어요."),
        DiscoveryTheme(id: "pet", title: "반려동물", symbol: "pawprint", prompt: "함께 걷기 편한 야외형 장소를 먼저 살펴봐요."),
        DiscoveryTheme(id: "meal", title: "식사", symbol: "fork.knife", prompt: "이동 부담이 낮은 식사 전후 코스로 이어집니다.")
    ]
}

private struct ThemePill: View {
    let theme: DiscoveryTheme
    let isSelected: Bool

    var body: some View {
        Label(theme.title, systemImage: theme.symbol)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(isSelected ? .white : .primary)
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background {
                Capsule(style: .continuous)
                    .fill(isSelected ? Color.blue.gradient : Color.white.opacity(0.42).gradient)
            }
            .overlay {
                Capsule(style: .continuous)
                    .stroke(isSelected ? Color.blue.opacity(0.45) : Color.primary.opacity(0.08), lineWidth: 1)
            }
            .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
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
            .background(.ultraThinMaterial, in: Capsule(style: .continuous))
            .padding(12)
        }
    }
}

private struct RecommendationCard: View {
    let card: RecommendationCardModel

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            RecommendationCardRow(card: card)
            HStack(spacing: 10) {
                NavigationLink(value: AppRoute.mapFocus(cardID: card.id)) {
                    Label("지도에서 확인", systemImage: "map")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)

                NavigationLink(value: AppRoute.recommendationDetail(cardID: card.id)) {
                    Label("추천 이유", systemImage: "sparkles")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
            }
            .font(.caption.weight(.semibold))
        }
        .padding(16)
        .homeRecommendationGlass(cornerRadius: 24, tint: .blue.opacity(0.12), interactive: true)
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

import SwiftUI
import PeroCore

struct HomeRecommendationScreen: View {
    @ObservedObject var viewModel: RecommendationViewModel

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
    }

    private var recommendationBackdrop: some View {
        LinearGradient(
            colors: [
                Color.blue.opacity(0.18),
                Color.cyan.opacity(0.10),
                Color(.systemGroupedBackground)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .ignoresSafeArea()
    }

    private var recommendationList: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 20) {
                heroSection
                stateSection
                recommendationSection
            }
            .padding(.horizontal, 20)
            .padding(.top, 28)
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
            Label("현재 위치 기준", systemImage: "location.fill")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.blue)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .homeRecommendationGlass(cornerRadius: 16, tint: .cyan.opacity(0.24))
            Text("지금 바로 갈 만한 장소")
                .font(.title2.weight(.bold))
            Text("가까운 순서만 보여주지 않고, 왜 이 장소가 지금 맞는지 먼저 설명합니다.")
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
                NavigationLink(value: AppRoute.recommendationDetail(card)) {
                    HStack(alignment: .center, spacing: 12) {
                        RecommendationCardRow(card: card)
                        Image(systemName: "chevron.right")
                            .font(.headline.weight(.semibold))
                            .foregroundStyle(.secondary.opacity(0.65))
                    }
                    .padding(16)
                    .homeRecommendationGlass(cornerRadius: 24, tint: .blue.opacity(0.12), interactive: true)
                }
                .buttonStyle(.plain)
            }
        }
    }
}

private struct RecommendationCardRow: View {
    let card: RecommendationCardModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(card.title)
                    .font(.headline)
                Spacer()
                Text(card.distanceLabel)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.blue)
            }
            Text(card.subtitle)
                .font(.subheadline.weight(.semibold))
            Text(card.reason)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            HStack {
                Label(card.district, systemImage: "mappin.and.ellipse")
                Label(card.category, systemImage: "tag")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
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

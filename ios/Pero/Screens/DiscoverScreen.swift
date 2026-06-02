import SwiftUI
import PeroCore

struct HomeRecommendationScreen: View {
    @ObservedObject var viewModel: RecommendationViewModel

    var body: some View {
        recommendationGlassContainer {
            recommendationList
        }
        .refreshable {
            await viewModel.loadGoNowRecommendations()
        }
        .animation(.default, value: viewModel.state)
    }

    private var recommendationList: some View {
        List {
            heroSection
            stateSection
            recommendationSection
        }
        .listStyle(.insetGrouped)
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
        Section {
            VStack(alignment: .leading, spacing: 14) {
                Label("현재 위치 기준", systemImage: "location.fill")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.blue)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .homeRecommendationGlass(cornerRadius: 14, tint: .blue.opacity(0.16))
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
                        .homeRecommendationGlass(cornerRadius: 12)
                }
            }
            .padding(16)
            .homeRecommendationGlass(cornerRadius: 24, tint: .blue.opacity(0.08))
        }
        .listRowBackground(Color.clear)
    }

    @ViewBuilder
    private var stateSection: some View {
        switch viewModel.state {
        case .ready:
            Section {
                StateMessageView(icon: "location", title: "위치 확인 대기", message: "시연용 기본 위치로 추천을 준비합니다.")
            }
        case .loading:
            Section("지금 갈 곳 찾는 중") {
                HStack(spacing: 12) {
                    ProgressView()
                    Text("장소 메타데이터와 추천 이유를 정리하고 있습니다.")
                        .foregroundStyle(.secondary)
                }
                .padding(14)
                .homeRecommendationGlass(cornerRadius: 18)
            }
        case .results:
            EmptyView()
        case .empty:
            Section {
                StateMessageView(icon: "tray", title: "추천 후보 없음", message: "반경을 넓히거나 백엔드 추천 데이터를 확인해 주세요.")
            }
        case .error(let message):
            Section {
                StateMessageView(icon: "exclamationmark.triangle", title: "연결 확인 필요", message: message)
            }
        }
    }

    private var recommendationSection: some View {
        Section(viewModel.state.title) {
            ForEach(viewModel.cards) { card in
                NavigationLink(value: AppRoute.recommendationDetail(card)) {
                    RecommendationCardRow(card: card)
                        .padding(12)
                        .homeRecommendationGlass(cornerRadius: 20, tint: .blue.opacity(0.06), interactive: true)
                }
                .listRowBackground(Color.clear)
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
        .padding(.vertical, 6)
        .accessibilityElement(children: .combine)
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
        .padding(14)
        .homeRecommendationGlass(cornerRadius: 18)
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

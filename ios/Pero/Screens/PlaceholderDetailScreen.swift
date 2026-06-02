import SwiftUI

struct PlaceExplanationDetailScreen: View {
    let card: RecommendationCardModel

    private var appleMapsURL: URL {
        let encodedTitle = card.title.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? card.title
        return URL(string: "http://maps.apple.com/?ll=\(card.latitude),\(card.longitude)&q=\(encodedTitle)")!
    }

    var body: some View {
        ZStack {
            detailBackdrop

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    reasonHero
                    actionRow
                    visitSummary
                    sourceAndTags
                }
                .padding(.horizontal, 20)
                .padding(.top, 24)
                .padding(.bottom, 36)
            }
            .scrollIndicators(.hidden)
        }
        .navigationTitle("추천 이유")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var detailBackdrop: some View {
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

    private var reasonHero: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 8) {
                    Label(card.subtitle, systemImage: "sparkles")
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(.blue)
                    Text(card.title)
                        .font(.largeTitle.weight(.bold))
                        .minimumScaleFactor(0.78)
                    Text(card.reason)
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
                CategoryBadge(category: card.category)
            }

            HStack(spacing: 10) {
                MetricPill(icon: "figure.walk", title: "거리", value: card.distanceLabel)
                MetricPill(icon: "mappin.and.ellipse", title: "지역", value: card.district)
            }
        }
        .padding(22)
        .detailScreenGlass(cornerRadius: 32, tint: .white.opacity(0.28), interactive: true)
    }

    private var actionRow: some View {
        HStack(spacing: 12) {
            NavigationLink(value: AppRoute.mapFocus(card)) {
                VStack(alignment: .leading, spacing: 8) {
                    Image(systemName: "map.fill")
                        .font(.title2.weight(.bold))
                    Text("지도에서 확인")
                        .font(.headline)
                    Text("전체 지도 위에서 위치와 이동감을 봅니다.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(16)
            }
            .buttonStyle(.plain)
            .detailScreenGlass(cornerRadius: 24, tint: .blue.opacity(0.16), interactive: true)

            Link(destination: appleMapsURL) {
                VStack(alignment: .leading, spacing: 8) {
                    Image(systemName: "arrow.triangle.turn.up.right.circle.fill")
                        .font(.title2.weight(.bold))
                    Text("길찾기 열기")
                        .font(.headline)
                    Text("애플 지도에서 바로 이동을 이어갑니다.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(16)
            }
            .buttonStyle(.plain)
            .detailScreenGlass(cornerRadius: 24, tint: .cyan.opacity(0.16), interactive: true)
        }
    }

    private var visitSummary: some View {
        VStack(alignment: .leading, spacing: 14) {
            DetailSectionTitle("방문 전에 확인")
            InfoLine(icon: "road.lanes", title: "주소", value: card.roadAddress)
            InfoLine(icon: "tag", title: "분류", value: card.category)
            InfoLine(icon: "scope", title: "추천 맥락", value: "가까운 순서보다 지금 설명 가능한 이유를 먼저 보여줍니다.")
        }
        .padding(18)
        .detailScreenGlass(cornerRadius: 26, tint: .white.opacity(0.22))
    }

    private var sourceAndTags: some View {
        VStack(alignment: .leading, spacing: 14) {
            DetailSectionTitle("근거와 태그")
            InfoLine(icon: "doc.text.magnifyingglass", title: "데이터 출처", value: card.sourceAttribution)
            FlowTagRow(tags: card.tags)
        }
        .padding(18)
        .detailScreenGlass(cornerRadius: 26, tint: .white.opacity(0.20))
    }
}

private struct CategoryBadge: View {
    let category: String

    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: iconName)
                .font(.title2.weight(.bold))
            Text(category)
                .font(.caption.weight(.bold))
                .lineLimit(1)
        }
        .foregroundStyle(.blue)
        .frame(width: 70, height: 70)
        .detailScreenGlass(cornerRadius: 22, tint: .blue.opacity(0.14))
    }

    private var iconName: String {
        switch category {
        case let value where value.contains("음식") || value.contains("식당"):
            "fork.knife.circle.fill"
        case let value where value.contains("전시") || value.contains("문화"):
            "building.columns.circle.fill"
        default:
            "leaf.circle.fill"
        }
    }
}

private struct MetricPill: View {
    let icon: String
    let title: String
    let value: String

    var body: some View {
        Label {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.secondary)
                Text(value)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.primary)
            }
        } icon: {
            Image(systemName: icon)
                .foregroundStyle(.blue)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .detailScreenGlass(cornerRadius: 18, tint: .white.opacity(0.18))
    }
}

private struct DetailSectionTitle: View {
    let title: String

    init(_ title: String) {
        self.title = title
    }

    var body: some View {
        Text(title)
            .font(.subheadline.weight(.bold))
            .foregroundStyle(.secondary)
    }
}

private struct InfoLine: View {
    let icon: String
    let title: String
    let value: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.headline)
                .foregroundStyle(.blue)
                .frame(width: 26)
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.secondary)
                Text(value)
                    .font(.subheadline)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

private struct FlowTagRow: View {
    let tags: [String]

    var body: some View {
        if tags.isEmpty {
            Text("태그 정보 없음")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        } else {
            ScrollView(.horizontal) {
                HStack(spacing: 8) {
                    ForEach(tags, id: \.self) { tag in
                        Text("#\(tag)")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(.blue)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .detailScreenGlass(cornerRadius: 16, tint: .blue.opacity(0.12))
                    }
                }
            }
            .scrollIndicators(.hidden)
        }
    }
}

private extension View {
    @ViewBuilder
    func detailScreenGlass(cornerRadius: CGFloat, tint: Color? = nil, interactive: Bool = false) -> some View {
        if #available(iOS 26, *) {
            let glass = interactive ? Glass.regular.tint(tint).interactive() : Glass.regular.tint(tint)

            self.glassEffect(glass, in: .rect(cornerRadius: cornerRadius))
        } else {
            self
                .background(.background.opacity(0.82), in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .stroke(.white.opacity(0.24), lineWidth: 1)
                }
        }
    }
}

#Preview {
    NavigationStack {
        PlaceExplanationDetailScreen(
            card: RecommendationCardModel(
                id: "preview",
                title: "서울숲",
                subtitle: "가까운 산책 추천",
                reason: "현재 위치에서 이동 부담이 낮고 설명 가능한 장소입니다.",
                category: "공원",
                district: "성동구",
                roadAddress: "서울특별시 성동구",
                latitude: 37.5446,
                longitude: 127.0374,
                distanceLabel: "1.8km",
                sourceAttribution: "Preview",
                tags: ["산책", "반려동물"]
            )
        )
    }
}

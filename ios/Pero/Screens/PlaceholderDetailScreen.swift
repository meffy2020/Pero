import SwiftUI

struct PlaceExplanationDetailScreen: View {
    let card: RecommendationCardModel

    private var mode: RecommendationPickerMode {
        RecommendationPickerMode(card: card)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header
                primaryActions
                visitSummary
                reasonSection
            }
            .padding(.horizontal, 18)
            .padding(.top, 18)
            .padding(.bottom, 36)
        }
        .background(PeroMapStyle.paper.ignoresSafeArea())
        .navigationTitle("상세")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(mode.title)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(PeroMapStyle.muted)
                    Text(card.title)
                        .font(.title2.weight(.bold))
                        .foregroundStyle(PeroMapStyle.ink)
                        .lineLimit(2)
                    Text(card.reason)
                        .font(.subheadline)
                        .foregroundStyle(PeroMapStyle.inkSoft)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 8)
                Image(systemName: mode.symbolName)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(PeroMapStyle.ink)
                    .frame(width: 44, height: 44)
                    .background(PeroMapStyle.accentPale, in: Circle())
            }

            FlowMetadataRow(card: card)
        }
        .padding(20)
        .peroFloatingSurface(cornerRadius: 24)
    }

    private var primaryActions: some View {
        HStack(spacing: 10) {
            NavigationLink(value: AppRoute.mapFocus(cardID: card.id)) {
                Label("지도", systemImage: "map")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(PeroMapStyle.accentDeep)

            if let appleMapsURL = card.appleMapsURL {
                Link(destination: appleMapsURL) {
                    Label("길찾기", systemImage: "arrow.triangle.turn.up.right.circle")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
            }
        }
        .font(.subheadline.weight(.semibold))
        .controlSize(.large)
    }

    private var visitSummary: some View {
        VStack(alignment: .leading, spacing: 14) {
            DetailSectionTitle("방문 정보")
            InfoLine(icon: "road.lanes", title: "주소", value: card.roadAddress)
            InfoLine(icon: "tag", title: "분류", value: card.category)
            InfoLine(icon: "mappin.and.ellipse", title: "지역", value: card.district)
        }
        .padding(18)
        .peroFloatingSurface(cornerRadius: 22)
    }

    private var reasonSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            DetailSectionTitle("왜 이 추천인가요")
            InfoLine(icon: "scope", title: "추천 맥락", value: mode.resultCopy(for: card))
            InfoLine(icon: "doc.text", title: "데이터 출처", value: card.sourceAttribution)
            FlowTagRow(tags: card.tags)
        }
        .padding(18)
        .peroFloatingSurface(cornerRadius: 22)
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
            .foregroundStyle(PeroMapStyle.ink)
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
                .foregroundStyle(PeroMapStyle.accentDeep)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(PeroMapStyle.muted)
                Text(value)
                    .font(.subheadline)
                    .foregroundStyle(PeroMapStyle.inkSoft)
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
                .foregroundStyle(PeroMapStyle.muted)
        } else {
            ScrollView(.horizontal) {
                HStack(spacing: 8) {
                    ForEach(tags, id: \.self) { tag in
                        Text("#\(tag)")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(PeroMapStyle.inkSoft)
                            .padding(.horizontal, 12)
                            .frame(height: 32)
                            .background(PeroMapStyle.surfaceMuted, in: Capsule())
                    }
                }
            }
            .scrollIndicators(.hidden)
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

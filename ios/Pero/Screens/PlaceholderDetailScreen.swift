import SwiftUI

struct PlaceExplanationDetailScreen: View {
    let card: RecommendationCardModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header
                primaryActions
                visitSummary
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
                    Text(card.category)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(PeroMapStyle.muted)
                    Text(card.title)
                        .font(.title2.weight(.bold))
                        .foregroundStyle(PeroMapStyle.ink)
                        .lineLimit(2)
                }
                Spacer(minLength: 8)
                PeroBrandLogoMark(size: 48)
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
            .buttonStyle(PeroActionButtonStyle())

            KakaoDirectionsButton(card: card)
                .buttonStyle(PeroActionButtonStyle())
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
            if let eventPeriodLabel = card.eventPeriodLabel {
                InfoLine(icon: "calendar", title: "일정", value: eventPeriodLabel)
            }
            if card.randomSlotKind == .festival, let eventSummary = card.eventSummary {
                InfoLine(icon: "text.alignleft", title: "행사 요약", value: eventSummary)
            }
            if let overview = card.detail?.overview, overview != card.eventSummary {
                InfoLine(icon: "doc.plaintext", title: "설명", value: overview)
            }
            if let fields = card.detail?.fields, !fields.isEmpty {
                ForEach(fields) { field in
                    InfoLine(icon: field.icon, title: field.title, value: field.value)
                }
            }
            if !card.tags.isEmpty {
                FlowTagRow(tags: card.tags)
            }
            if let officialURL = card.officialURL {
                Link(destination: officialURL) {
                    Label("공식 사이트", systemImage: "safari")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(PeroActionButtonStyle())
            }
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

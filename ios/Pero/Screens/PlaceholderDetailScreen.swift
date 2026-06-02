import SwiftUI

struct PlaceExplanationDetailScreen: View {
    let card: RecommendationCardModel

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 12) {
                    Text(card.subtitle)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.blue)
                    Text(card.title)
                        .font(.title2.weight(.bold))
                    Text(card.reason)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 4)
            }

            Section("추천 근거") {
                Label(card.distanceLabel, systemImage: "figure.walk")
                Label(card.roadAddress, systemImage: "mappin.and.ellipse")
                Label(card.sourceAttribution, systemImage: "doc.text.magnifyingglass")
            }

            Section("태그") {
                FlowTagRow(tags: card.tags)
            }

            Section {
                NavigationLink(value: AppRoute.mapFocus(card)) {
                    Label("지도에서 위치 확인", systemImage: "map")
                }
            }
        }
        .navigationTitle("추천 이유")
    }
}

private struct FlowTagRow: View {
    let tags: [String]

    var body: some View {
        if tags.isEmpty {
            Text("태그 정보 없음")
                .foregroundStyle(.secondary)
        } else {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(tags, id: \.self) { tag in
                    Text("#\(tag)")
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(.blue.opacity(0.08), in: Capsule())
                }
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

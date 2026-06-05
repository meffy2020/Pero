import SwiftUI

struct MapScreen: View {
    @Environment(\.dismiss) private var dismiss

    let card: RecommendationCardModel
    @State private var camera: KakaoMapCamera

    init(card: RecommendationCardModel) {
        self.card = card
        _camera = State(initialValue: KakaoMapCamera(latitude: card.latitude, longitude: card.longitude, level: 5))
    }

    private var mode: RecommendationPickerMode {
        RecommendationPickerMode(card: card)
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            ZStack {
                GeometryReader { proxy in
                    KakaoMapView(
                        camera: $camera,
                        markers: [KakaoMapMarker(id: card.id, latitude: card.latitude, longitude: card.longitude, isSelected: true)]
                    )
                    .frame(width: proxy.size.width, height: proxy.size.height)
                    .ignoresSafeArea()
                }
                .ignoresSafeArea()

            }
            .ignoresSafeArea()

            VStack(spacing: 0) {
                topContextBar
                Spacer(minLength: 0)
                bottomSummaryPanel
            }
            .padding(.horizontal, 16)
            .safeAreaPadding(.top, 10)
            .safeAreaPadding(.bottom, 12)
        }
        .background(PeroMapStyle.paper)
        .toolbar(.hidden, for: .navigationBar)
    }

    private var topContextBar: some View {
        HStack(spacing: 10) {
            Button {
                dismiss()
            } label: {
                Image(systemName: "chevron.left")
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(PeroMapStyle.ink)
                    .frame(width: 44, height: 44)
            }
            .buttonStyle(.plain)
            .peroFloatingSurface(cornerRadius: 22)
            .accessibilityLabel("뒤로")

            HStack(spacing: 8) {
                Image(systemName: mode.symbolName)
                    .foregroundStyle(PeroMapStyle.accentDeep)
                Text(mode.title)
                Text("·")
                    .foregroundStyle(PeroMapStyle.muted)
                Text(card.distanceLabel)
                Text("·")
                    .foregroundStyle(PeroMapStyle.muted)
                Text(card.district)
            }
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(PeroMapStyle.ink)
            .lineLimit(1)
            .padding(.horizontal, 14)
            .frame(height: 44)
            .peroFloatingSurface(cornerRadius: 22)

            Spacer(minLength: 0)
        }
    }

    private var bottomSummaryPanel: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 6) {
                Text("선택한 위치")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(PeroMapStyle.muted)
                Text(card.title)
                    .font(.title3.weight(.bold))
                    .foregroundStyle(PeroMapStyle.ink)
                    .lineLimit(2)
            }

            FlowMetadataRow(card: card)

            VStack(alignment: .leading, spacing: 8) {
                Label(card.roadAddress, systemImage: "road.lanes")
                Label("출처: \(card.sourceAttribution)", systemImage: "doc.text")
            }
            .font(.caption)
            .foregroundStyle(PeroMapStyle.inkSoft)

            HStack(spacing: 10) {
                if let appleMapsURL = card.appleMapsURL {
                    Link(destination: appleMapsURL) {
                        Label("길찾기", systemImage: "arrow.triangle.turn.up.right.circle")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(PeroMapStyle.accentDeep)
                }

                NavigationLink(value: AppRoute.recommendationDetail(cardID: card.id)) {
                    Label("상세", systemImage: "info.circle")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
            }
            .font(.subheadline.weight(.semibold))
        }
        .padding(.top, 22)
        .padding(.horizontal, 20)
        .padding(.bottom, 18)
        .peroBottomSheetSurface()
    }
}

#Preview {
    NavigationStack {
        MapScreen(
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

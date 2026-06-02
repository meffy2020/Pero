import SwiftUI
import MapKit

struct MapScreen: View {
    let card: RecommendationCardModel

    private var position: MapCameraPosition {
        .region(
            MKCoordinateRegion(
                center: CLLocationCoordinate2D(latitude: card.latitude, longitude: card.longitude),
                span: MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)
            )
        )
    }

    var body: some View {
        VStack(spacing: 0) {
            Map(initialPosition: position) {
                Marker(card.title, coordinate: CLLocationCoordinate2D(latitude: card.latitude, longitude: card.longitude))
            }
            .frame(maxHeight: .infinity)

            VStack(alignment: .leading, spacing: 10) {
                Text(card.title)
                    .font(.headline)
                Text(card.reason)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                HStack {
                    Label(card.distanceLabel, systemImage: "figure.walk")
                    Spacer()
                    Text(card.district)
                }
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            }
            .padding()
            .background(.regularMaterial)
        }
        .navigationTitle("지도 확인")
        .navigationBarTitleDisplayMode(.inline)
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

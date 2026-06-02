import MapKit
import SwiftUI

struct MapScreen: View {
  let card: RecommendationCardModel

  private var coordinate: CLLocationCoordinate2D {
    CLLocationCoordinate2D(latitude: card.latitude, longitude: card.longitude)
  }

  private var position: MapCameraPosition {
    .region(
      MKCoordinateRegion(
        center: coordinate,
        span: MKCoordinateSpan(latitudeDelta: 0.008, longitudeDelta: 0.008)
      )
    )
  }

  var body: some View {
    ZStack(alignment: .bottom) {
      Map(initialPosition: position) {
        Annotation(card.title, coordinate: coordinate) {
          VStack(spacing: 6) {
            Image(systemName: "pawprint.circle.fill")
              .font(.system(size: 34, weight: .bold))
              .foregroundStyle(.white, .blue.gradient)
              .shadow(color: .black.opacity(0.22), radius: 10, y: 4)
            Text(card.title)
              .font(.caption.weight(.bold))
              .foregroundStyle(.primary)
              .padding(.horizontal, 10)
              .padding(.vertical, 6)
              .mapScreenGlass(cornerRadius: 14, tint: .white.opacity(0.30))
          }
        }
      }
      .mapStyle(
        .standard(
          elevation: .realistic, pointsOfInterest: .including([.park, .restaurant, .museum]))
      )
      .ignoresSafeArea(edges: .bottom)

      VStack(spacing: 0) {
        topContextBar
        Spacer()
        bottomSummaryPanel
      }
      .padding(.horizontal, 18)
      .padding(.top, 12)
      .padding(.bottom, 18)
    }
    .background(Color(.systemGroupedBackground))
    .navigationTitle("지도 확인")
    .navigationBarTitleDisplayMode(.inline)
  }

  private var topContextBar: some View {
    HStack(spacing: 8) {
      Label(card.distanceLabel, systemImage: "figure.walk")
      Label(card.district, systemImage: "mappin.and.ellipse")
      Spacer(minLength: 0)
    }
    .font(.caption.weight(.bold))
    .foregroundStyle(.primary)
    .padding(.horizontal, 12)
    .padding(.vertical, 10)
    .mapScreenGlass(cornerRadius: 18, tint: .cyan.opacity(0.20))
  }

  private var bottomSummaryPanel: some View {
    VStack(alignment: .leading, spacing: 16) {
      HStack(alignment: .top, spacing: 12) {
        VStack(alignment: .leading, spacing: 7) {
          Text(card.subtitle)
            .font(.caption.weight(.bold))
            .foregroundStyle(.blue)
          Text(card.title)
            .font(.title2.weight(.bold))
          Text(card.reason)
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
        }
        Spacer()
        Image(systemName: iconName)
          .font(.title2.weight(.bold))
          .foregroundStyle(.blue)
          .frame(width: 48, height: 48)
          .mapScreenGlass(cornerRadius: 18, tint: .blue.opacity(0.14))
      }

      VStack(alignment: .leading, spacing: 8) {
        Label(card.roadAddress, systemImage: "road.lanes")
        Label("출처: \(card.sourceAttribution)", systemImage: "doc.text.magnifyingglass")
      }
      .font(.caption)
      .foregroundStyle(.secondary)

      HStack(spacing: 10) {
        Link(destination: appleMapsURL) {
          Label("애플 지도 열기", systemImage: "arrow.up.right.square")
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)

        NavigationLink(value: AppRoute.recommendationDetail(card)) {
          Label("추천 이유", systemImage: "sparkles")
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.bordered)
        .controlSize(.large)
      }
      .font(.subheadline.weight(.semibold))
    }
    .padding(18)
    .mapScreenGlass(cornerRadius: 30, tint: .white.opacity(0.34), interactive: true)
    .shadow(color: .black.opacity(0.14), radius: 24, y: 14)
  }

  private var iconName: String {
    switch card.category {
    case let value where value.contains("음식") || value.contains("식당"):
      "fork.knife.circle.fill"
    case let value where value.contains("전시") || value.contains("문화"):
      "building.columns.circle.fill"
    default:
      "leaf.circle.fill"
    }
  }

  private var appleMapsURL: URL {
    let encodedTitle =
      card.title.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? card.title
    return URL(
      string: "http://maps.apple.com/?ll=\(card.latitude),\(card.longitude)&q=\(encodedTitle)")!
  }
}

extension View {
  @ViewBuilder
  fileprivate func mapScreenGlass(
    cornerRadius: CGFloat, tint: Color? = nil, interactive: Bool = false
  ) -> some View {
    if #available(iOS 26, *) {
      let glass = interactive ? Glass.regular.tint(tint).interactive() : Glass.regular.tint(tint)

      self.glassEffect(glass, in: .rect(cornerRadius: cornerRadius))
    } else {
      self
        .background(
          .regularMaterial, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        )
        .overlay {
          RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .stroke(.white.opacity(0.28), lineWidth: 1)
        }
    }
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

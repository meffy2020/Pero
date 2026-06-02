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

  private var slot: RandomRecommendationSlot {
    RandomRecommendationSlot(card: card)
  }

  var body: some View {
    ZStack(alignment: .bottom) {
      Map(initialPosition: position) {
        Annotation(card.title, coordinate: coordinate) {
          VStack(spacing: 6) {
            Image(systemName: slot.symbolName)
              .font(.system(size: 34, weight: .bold))
              .foregroundStyle(.white, slot.accent.gradient)
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
      Label(slot.mapEyebrow, systemImage: slot.symbolName)
      Label(card.distanceLabel, systemImage: "figure.walk")
      Label(card.district, systemImage: "mappin.and.ellipse")
      Spacer(minLength: 0)
    }
    .font(.caption.weight(.bold))
    .foregroundStyle(.primary)
    .padding(.horizontal, 12)
    .padding(.vertical, 10)
    .mapScreenGlass(cornerRadius: 18, tint: slot.accent.opacity(0.20))
  }

  private var bottomSummaryPanel: some View {
    VStack(alignment: .leading, spacing: 16) {
      HStack(alignment: .top, spacing: 12) {
        VStack(alignment: .leading, spacing: 7) {
          Text(slot.detailEyebrow)
            .font(.caption.weight(.bold))
            .foregroundStyle(slot.accent)
          Text(card.title)
            .font(.title2.weight(.bold))
          Text(slot.mapSummary(for: card))
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
        }
        Spacer()
        Image(systemName: slot.symbolName)
          .font(.title2.weight(.bold))
          .foregroundStyle(slot.accent)
          .frame(width: 48, height: 48)
          .mapScreenGlass(cornerRadius: 18, tint: slot.accent.opacity(0.14))
      }

      VStack(alignment: .leading, spacing: 8) {
        Label(card.roadAddress, systemImage: "road.lanes")
        Label(slot.explainabilityCopy, systemImage: "sparkles")
        Label("출처: \(card.sourceAttribution)", systemImage: "doc.text.magnifyingglass")
      }
      .font(.caption)
      .foregroundStyle(.secondary)

      HStack(spacing: 10) {
        if let appleMapsURL = card.appleMapsURL {
          Link(destination: appleMapsURL) {
            Label("애플 지도 열기", systemImage: "arrow.up.right.square")
              .frame(maxWidth: .infinity)
          }
          .buttonStyle(.borderedProminent)
          .controlSize(.large)
        } else {
          Label("지도 링크 없음", systemImage: "exclamationmark.triangle")
            .frame(maxWidth: .infinity)
            .buttonStyle(.bordered)
            .controlSize(.large)
        }

        NavigationLink(value: AppRoute.recommendationDetail(cardID: card.id)) {
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

}

private enum RandomRecommendationSlot {
  case place
  case restaurant
  case course

  init(card: RecommendationCardModel) {
    let source = "\(card.subtitle) \(card.category) \(card.title)"
    if source.contains("코스") || source.contains("차") || source.localizedCaseInsensitiveContains("course") {
      self = .course
    } else if source.contains("식사") || source.contains("식당") || source.contains("음식") || source.contains("카페") || source.localizedCaseInsensitiveContains("meal") {
      self = .restaurant
    } else {
      self = .place
    }
  }

  var mapEyebrow: String {
    switch self {
    case .place: "랜덤 장소"
    case .restaurant: "식당 추천"
    case .course: "랜덤 코스"
    }
  }

  var detailEyebrow: String {
    switch self {
    case .place: "오늘 뽑힌 랜덤 장소"
    case .restaurant: "지금 먹기 좋은 식당 추천"
    case .course: "바로 이어지는 랜덤 코스"
    }
  }

  var explainabilityCopy: String {
    switch self {
    case .place: "장소성, 거리, 태그를 함께 보고 뽑은 결과입니다"
    case .restaurant: "식사 맥락과 다음 이동 부담을 함께 보고 뽑은 결과입니다"
    case .course: "첫 목적지와 다음 동선을 함께 상상할 수 있게 뽑은 결과입니다"
    }
  }

  var symbolName: String {
    switch self {
    case .place: "sparkles.square.filled.on.square"
    case .restaurant: "fork.knife.circle.fill"
    case .course: "point.topleft.down.curvedto.point.bottomright.up.fill"
    }
  }

  var accent: Color {
    switch self {
    case .place: .blue
    case .restaurant: .orange
    case .course: .purple
    }
  }

  func mapSummary(for card: RecommendationCardModel) -> String {
    "\(explainabilityCopy) \(card.reason)"
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
          .background.opacity(0.92),
          in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
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

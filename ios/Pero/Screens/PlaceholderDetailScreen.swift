import SwiftUI

struct PlaceExplanationDetailScreen: View {
  let card: RecommendationCardModel

  private var slot: DetailRecommendationSlot {
    DetailRecommendationSlot(card: card)
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
        slot.accent.opacity(0.18),
        slot.secondaryAccent.opacity(0.10),
        Color(.systemGroupedBackground),
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
          Label(slot.heroEyebrow, systemImage: slot.symbolName)
            .font(.subheadline.weight(.bold))
            .foregroundStyle(slot.accent)
          Text(card.title)
            .font(.largeTitle.weight(.bold))
            .minimumScaleFactor(0.78)
          Text(slot.heroReason(for: card))
            .font(.body)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
        }
        Spacer()
        CategoryBadge(category: slot.badgeTitle, iconName: slot.symbolName, accent: slot.accent)
      }

      HStack(spacing: 10) {
        MetricPill(icon: "figure.walk", title: "거리", value: card.distanceLabel)
        MetricPill(icon: "mappin.and.ellipse", title: "지역", value: card.district)
      }
    }
    .padding(22)
    .detailScreenGlass(cornerRadius: 32, tint: slot.accent.opacity(0.16), interactive: true)
  }

  private var actionRow: some View {
    HStack(spacing: 12) {
      NavigationLink(value: AppRoute.mapFocus(cardID: card.id)) {
        VStack(alignment: .leading, spacing: 8) {
          Image(systemName: "map.fill")
            .font(.title2.weight(.bold))
          Text("지도에서 확인")
            .font(.headline)
          Text(slot.mapCTACopy)
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
      }
      .buttonStyle(.plain)
      .detailScreenGlass(cornerRadius: 24, tint: slot.accent.opacity(0.16), interactive: true)

      if let appleMapsURL = card.appleMapsURL {
        Link(destination: appleMapsURL) {
          VStack(alignment: .leading, spacing: 8) {
            Image(systemName: "arrow.triangle.turn.up.right.circle.fill")
              .font(.title2.weight(.bold))
            Text("길찾기 열기")
              .font(.headline)
            Text(slot.directionsCTACopy)
              .font(.caption)
              .foregroundStyle(.secondary)
          }
          .frame(maxWidth: .infinity, alignment: .leading)
          .padding(16)
        }
        .buttonStyle(.plain)
        .detailScreenGlass(cornerRadius: 24, tint: slot.secondaryAccent.opacity(0.16), interactive: true)
      } else {
        VStack(alignment: .leading, spacing: 8) {
          Image(systemName: "exclamationmark.triangle.fill")
            .font(.title2.weight(.bold))
          Text("지도 링크 없음")
            .font(.headline)
          Text("장소 좌표를 다시 확인해 주세요.")
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .detailScreenGlass(cornerRadius: 24, tint: .gray.opacity(0.12))
      }
    }
  }

  private var visitSummary: some View {
    VStack(alignment: .leading, spacing: 14) {
      DetailSectionTitle(slot.visitSectionTitle)
      InfoLine(icon: "road.lanes", title: "주소", value: card.roadAddress)
      InfoLine(icon: "tag", title: "분류", value: card.category)
      InfoLine(icon: "scope", title: "추천 맥락", value: slot.contextCopy)
    }
    .padding(18)
    .detailScreenGlass(cornerRadius: 26, tint: slot.accent.opacity(0.12))
  }

  private var sourceAndTags: some View {
    VStack(alignment: .leading, spacing: 14) {
      DetailSectionTitle("왜 이 추천을 뽑았나요")
      InfoLine(icon: "sparkles", title: "추천 방식", value: slot.explainabilityCopy)
      InfoLine(icon: "doc.text.magnifyingglass", title: "데이터 출처", value: card.sourceAttribution)
      FlowTagRow(tags: card.tags)
    }
    .padding(18)
    .detailScreenGlass(cornerRadius: 26, tint: slot.secondaryAccent.opacity(0.12))
  }
}


private enum DetailRecommendationSlot {
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

  var heroEyebrow: String {
    switch self {
    case .place: "랜덤 장소가 뽑혔어요"
    case .restaurant: "식당 추천을 뽑았어요"
    case .course: "랜덤 코스의 시작점이에요"
    }
  }

  var badgeTitle: String {
    switch self {
    case .place: "장소"
    case .restaurant: "식당"
    case .course: "코스"
    }
  }

  var visitSectionTitle: String {
    switch self {
    case .place: "방문 전에 확인"
    case .restaurant: "먹기 전에 확인"
    case .course: "코스 전에 확인"
    }
  }

  var contextCopy: String {
    switch self {
    case .place: "조건을 많이 고르지 않아도 지금 설명 가능한 장소를 먼저 보여줍니다."
    case .restaurant: "식사하기 좋은 맥락과 다음 장소로 이동하기 쉬운지를 함께 보여줍니다."
    case .course: "첫 장소에서 다음 움직임까지 상상할 수 있도록 코스의 시작점을 먼저 보여줍니다."
    }
  }

  var explainabilityCopy: String {
    switch self {
    case .place: "거리, 지역, 태그, 장소 메타데이터를 조합해 무작위처럼 가볍게 시작할 수 있게 정리했습니다."
    case .restaurant: "식사 카테고리와 이동 부담, 장소 설명을 함께 묶어 지금 먹기 좋은 후보로 정리했습니다."
    case .course: "단일 장소 추천을 넘어 다음 동선의 맥락을 읽을 수 있도록 코스형 추천으로 정리했습니다."
    }
  }

  var mapCTACopy: String {
    switch self {
    case .place: "지도 위에서 랜덤 장소의 위치감을 봅니다."
    case .restaurant: "식사 전후 이동 동선을 지도에서 봅니다."
    case .course: "코스 시작 위치와 다음 이동감을 지도에서 봅니다."
    }
  }

  var directionsCTACopy: String {
    switch self {
    case .place: "애플 지도에서 바로 장소 이동을 이어갑니다."
    case .restaurant: "애플 지도에서 식당까지 바로 이어갑니다."
    case .course: "애플 지도에서 코스 시작점까지 이어갑니다."
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

  var secondaryAccent: Color {
    switch self {
    case .place: .cyan
    case .restaurant: .yellow
    case .course: .indigo
    }
  }

  func heroReason(for card: RecommendationCardModel) -> String {
    "\(contextCopy) \(card.reason)"
  }
}

private struct CategoryBadge: View {
  let category: String
  let iconName: String
  let accent: Color

  var body: some View {
    VStack(spacing: 6) {
      Image(systemName: iconName)
        .font(.title2.weight(.bold))
      Text(category)
        .font(.caption.weight(.bold))
        .lineLimit(1)
    }
    .foregroundStyle(accent)
    .frame(width: 70, height: 70)
    .detailScreenGlass(cornerRadius: 22, tint: accent.opacity(0.14))
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

extension View {
  @ViewBuilder
  fileprivate func detailScreenGlass(
    cornerRadius: CGFloat, tint: Color? = nil, interactive: Bool = false
  ) -> some View {
    if #available(iOS 26, *) {
      let glass = interactive ? Glass.regular.tint(tint).interactive() : Glass.regular.tint(tint)

      self.glassEffect(glass, in: .rect(cornerRadius: cornerRadius))
    } else {
      self
        .background(
          .background.opacity(0.82),
          in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        )
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

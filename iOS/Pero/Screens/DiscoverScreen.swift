import SwiftUI

enum DiscoverDemoState: String, CaseIterable, Identifiable {
    case ready
    case loading
    case results
    case empty
    case error

    var id: String { rawValue }

    var title: String {
        switch self {
        case .ready: "탐색 준비"
        case .loading: "장소 불러오는 중"
        case .results: "추천 결과"
        case .empty: "조건에 맞는 장소 없음"
        case .error: "연결 확인 필요"
        }
    }
}

struct DiscoverScreen: View {
    @State private var query = "조용한 산책"
    @State private var demoState: DiscoverDemoState = .results

    private let themes = ["조용한 산책", "반려동물 동반", "비 오는 날 실내"]
    private let places = [
        PlacePreview(name: "서울숲", district: "성동구", reason: "산책로와 휴식 공간이 넓어 조용한 이동에 적합합니다."),
        PlacePreview(name: "문화비축기지", district: "마포구", reason: "실내 전시와 야외 동선이 함께 있어 날씨 변화에 대응하기 좋습니다."),
        PlacePreview(name: "북서울꿈의숲", district: "강북구", reason: "가족·반려동물과 걷기 좋은 넓은 공원형 장소입니다.")
    ]

    var body: some View {
        List {
            heroSection
            searchSection
            stateSection
            themeSection
        }
        .animation(.default, value: demoState)
    }

    private var heroSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 10) {
                Text("Pero 모바일 MVP")
                    .font(.title2.weight(.semibold))
                Text("취향과 상황에 맞는 관광 테마를 고르면, 지도로 장소를 탐색하고 상세 정보를 해석할 수 있습니다.")
                    .foregroundStyle(.secondary)
                Label("테마 선택 → 지도 탐색 → 장소 상세 해석", systemImage: "point.topleft.down.curvedto.point.bottomright.up")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .padding(.vertical, 4)
        }
    }

    private var searchSection: some View {
        Section("자연어 검색") {
            TextField("예: 비 오는 날 실내 데이트", text: $query)
                .textInputAutocapitalization(.never)
                .submitLabel(.search)
            Picker("화면 상태", selection: $demoState) {
                ForEach(DiscoverDemoState.allCases) { state in
                    Text(state.title).tag(state)
                }
            }
        }
    }

    @ViewBuilder
    private var stateSection: some View {
        Section(demoState.title) {
            switch demoState {
            case .ready:
                StateMessageView(
                    icon: "magnifyingglass",
                    title: "궁금한 장소 조건을 입력해 주세요",
                    message: "분위기, 동행자, 날씨, 이동 목적을 한국어 문장으로 적으면 추천 후보를 준비합니다."
                )
            case .loading:
                HStack(spacing: 12) {
                    ProgressView()
                    VStack(alignment: .leading, spacing: 4) {
                        Text("추천 장소를 정리하는 중입니다")
                            .font(.headline)
                        Text("장소 메타데이터와 지도 표시 정보를 함께 불러오고 있습니다.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 8)
            case .results:
                ForEach(places) { place in
                    NavigationLink(value: AppRoute.place(place.name)) {
                        PlacePreviewRow(place: place)
                    }
                }
            case .empty:
                StateMessageView(
                    icon: "tray",
                    title: "조건에 맞는 장소를 찾지 못했습니다",
                    message: "지역 범위를 넓히거나 ‘조용한’, ‘실내’, ‘산책’처럼 조건을 줄여 다시 검색해 보세요."
                )
            case .error:
                StateMessageView(
                    icon: "exclamationmark.triangle",
                    title: "검색 서버에 연결할 수 없습니다",
                    message: "네트워크 상태를 확인한 뒤 잠시 후 다시 시도해 주세요. 저장된 장소 화면은 계속 사용할 수 있습니다."
                )
            }
        }
    }

    private var themeSection: some View {
        Section("빠른 테마") {
            ForEach(themes, id: \.self) { theme in
                NavigationLink(value: AppRoute.theme(theme)) {
                    Label(theme, systemImage: "sparkles")
                }
            }
        }
    }
}

struct PlacePreview: Identifiable, Hashable {
    let name: String
    let district: String
    let reason: String

    var id: String { name }
}

private struct PlacePreviewRow: View {
    let place: PlacePreview

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(place.name)
                    .font(.headline)
                Spacer()
                Text(place.district)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Text(place.reason)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
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
        .padding(.vertical, 8)
    }
}

#Preview {
    NavigationStack {
        DiscoverScreen()
    }
}

import SwiftUI

struct DiscoverScreen: View {
    private let themes = ["조용한 산책", "반려동물 동반", "비 오는 날 실내"]

    var body: some View {
        List {
            Section {
                Text("취향과 상황에 맞는 관광 테마를 고르면, 지도로 장소를 탐색하고 상세 정보를 해석할 수 있습니다.")
                    .foregroundStyle(.secondary)
            }

            Section("추천 테마") {
                ForEach(themes, id: \.self) { theme in
                    NavigationLink(value: AppRoute.theme(theme)) {
                        Label(theme, systemImage: "sparkles")
                    }
                }
            }
        }
    }
}

#Preview {
    NavigationStack {
        DiscoverScreen()
    }
}

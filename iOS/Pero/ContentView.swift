import SwiftUI

struct ContentView: View {
    @State private var selectedTab: AppTab = .discover
    @State private var discoverPath: [AppRoute] = []
    @State private var mapPath: [AppRoute] = []
    @State private var savedPath: [AppRoute] = []

    var body: some View {
        TabView(selection: $selectedTab) {
            NavigationStack(path: $discoverPath) {
                DiscoverScreen()
                    .navigationTitle(AppTab.discover.title)
                    .navigationDestination(for: AppRoute.self, destination: routeView)
            }
            .tabItem { Label(AppTab.discover.title, systemImage: AppTab.discover.systemImage) }
            .tag(AppTab.discover)

            NavigationStack(path: $mapPath) {
                MapScreen()
                    .navigationTitle(AppTab.map.title)
                    .navigationDestination(for: AppRoute.self, destination: routeView)
            }
            .tabItem { Label(AppTab.map.title, systemImage: AppTab.map.systemImage) }
            .tag(AppTab.map)

            NavigationStack(path: $savedPath) {
                SavedPlacesScreen()
                    .navigationTitle(AppTab.saved.title)
                    .navigationDestination(for: AppRoute.self, destination: routeView)
            }
            .tabItem { Label(AppTab.saved.title, systemImage: AppTab.saved.systemImage) }
            .tag(AppTab.saved)
        }
    }

    @ViewBuilder
    private func routeView(for route: AppRoute) -> some View {
        switch route {
        case .theme(let name):
            PlaceholderDetailScreen(title: name, message: "테마에 맞는 장소 목록과 지도 연결을 준비 중입니다.")
        case .place(let name):
            PlaceholderDetailScreen(title: name, message: "장소 메타데이터와 추천 근거를 보여줄 예정입니다.")
        case .search(let query):
            PlaceholderDetailScreen(title: "\(query) 검색", message: "자연어 검색 결과를 모바일 흐름에 맞게 연결할 예정입니다.")
        }
    }
}

#Preview {
    ContentView()
}

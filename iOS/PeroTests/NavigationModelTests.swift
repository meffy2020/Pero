import Testing
@testable import Pero

struct NavigationModelTests {
    @Test func appTabsExposeKoreanLabelsInShellOrder() {
        #expect(AppTab.allCases.map(\.title) == ["탐색", "지도", "저장"])
        #expect(AppTab.allCases.map(\.systemImage) == ["sparkle.magnifyingglass", "map", "bookmark"])
    }

    @Test func routesAreHashableForNavigationStackPath() {
        let routes: Set<AppRoute> = [.theme("조용한 산책"), .place("서울숲"), .search("비 오는 날 실내")]
        #expect(routes.count == 3)
    }
}

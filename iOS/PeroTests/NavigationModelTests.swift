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

    @Test func discoverScreenStatesExposeKoreanCopy() {
        #expect(DiscoverDemoState.allCases.map(\.title) == [
            "탐색 준비",
            "장소 불러오는 중",
            "추천 결과",
            "조건에 맞는 장소 없음",
            "연결 확인 필요"
        ])
    }
}

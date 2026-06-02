# Pero iOS 디자인 리포트 기반 리디자인 검증

## 범위

- 기준 문서: `.omx/specs/deep-interview-pero-ios-design-report.md`
- 참고 리서치: `.lazyweb/design-research/pero-ios-app-design-2026-06-02/report.html` (로컬 캐시, 커밋 제외)
- 목표: iOS 네이티브 앱의 Home/Map/Detail 흐름을 `map-as-primary` 시연 흐름으로 보이게 정리한다.
- 비목표: 백엔드 API 계약 변경 없음, 실제 검색/필터 랭킹 개선 없음, 외부 의존성 추가 없음.

## 변경 요약

- Home/Discover
  - 지도 우선 발견 카드와 한국어 테마 rail을 추가했다.
  - 추천 카드에 거리, 지역, 카테고리, 태그, 추천 이유 CTA를 강조했다.
- Map
  - 전체 지도 위에 메타데이터 칩, 하단 요약 패널, `애플 지도 열기`/`추천 이유` CTA를 배치했다.
  - Apple Maps URL은 `RecommendationCardModel.appleMapsURL` helper를 공통으로 사용한다.
- Detail
  - 추천 이유를 첫 화면의 주 설명으로 올리고, 거리/지역/주소/분류/추천 맥락/태그를 읽기 쉽게 분리했다.
  - 지도/길찾기 CTA도 같은 route ID와 Apple Maps URL helper를 사용한다.
- Navigation boundary
  - `AppRoute`는 전체 `RecommendationCardModel` payload가 아니라 stable `cardID`만 가진다.
  - destination은 `RecommendationViewModel.card(for:)`로 현재 추천 목록에서 resolve한다.
- Preview runtime
  - `PERO_USE_PREVIEW=1`이면 API provider와 location provider를 모두 오프라인 preview/static으로 고정해 시뮬레이터 검증이 위치 권한/백엔드 상태에 흔들리지 않게 했다.

## 시뮬레이터 검증

- Scheme: `Pero`
- Project: `/Users/ksj/Desktop/02_Work/Projects/Pero/ios/Pero.xcodeproj`
- Simulator: `iPhone 17 Pro`, iOS Simulator `26.5`, id `78867352-14AD-4092-BDF0-46DE89BD3A79`
- Bundle ID: `com.pero.ios`
- Runtime env: `PERO_USE_PREVIEW=1`

### Screenshots

- Home: `.omx/evidence/ios-design-g002/home.jpg`
- Map: `.omx/evidence/ios-design-g002/map.jpg`
- Detail: `.omx/evidence/ios-design-g002/detail.jpg`
- G003 post-review Home: `.omx/evidence/ios-design-g002/home-post-review.jpg`

### Checks

- PASS: XcodeBuildMCP `build_sim` on `Pero` / `iPhone 17 Pro` / iOS `26.5`
  - log: `/Users/ksj/Library/Developer/XcodeBuildMCP/workspaces/Pero-51ba591fe951/logs/build_sim_2026-06-02T11-48-44-366Z_pid5033_2bef7277.log`
- PASS: XcodeBuildMCP `build_run_sim` after CoreSimulator recovery
  - log: `/Users/ksj/Library/Developer/XcodeBuildMCP/workspaces/Pero-51ba591fe951/logs/build_run_sim_2026-06-02T11-56-21-639Z_pid5033_cb0a8297.log`
- PASS: XcodeBuildMCP `launch_app_sim(env: { PERO_USE_PREVIEW: 1 })`
  - runtime log: `/Users/ksj/Library/Developer/XcodeBuildMCP/workspaces/Pero-51ba591fe951/logs/com.pero.ios_2026-06-02T11-58-10-343Z_helperpid65632_ownerpid5033_0d03f8c3.log`
- PASS: XcodeBuildMCP `wait_for_ui(textContains: 지도 우선 탐색)` and preview recommendation snapshot containing `현재 위치 37.5665, 126.9780`, `서울 반려 산책 공원`, `지도에서 확인`, `추천 이유 보기`
- PASS: XcodeBuildMCP `screenshot(returnFormat: path)` copied to `.omx/evidence/ios-design-g002/home-post-review.jpg`
- PASS: XcodeBuildMCP `test_sim` — 7 passed, 0 failed
  - log: `/Users/ksj/Library/Developer/XcodeBuildMCP/workspaces/Pero-51ba591fe951/logs/test_sim_2026-06-02T11-58-32-400Z_pid5033_f6c5cc99.log`
  - xcresult: `/Users/ksj/Library/Developer/XcodeBuildMCP/workspaces/Pero-51ba591fe951/result-bundles/test_sim_2026-06-02T11-58-32-400Z_pid5033_7245f704.xcresult`
- PASS: `swift test --package-path ios/PeroCore` — 6 passed, 0 failed
- PASS: `git diff --check`

### Simulator caveat

- Earlier post-review XcodeBuildMCP launch/test attempts hung in CoreSimulator `simctl` install/terminate calls.
- Recovery used local simulator-process cleanup, then `build_run_sim`, explicit `launch_app_sim(env: PERO_USE_PREVIEW=1)`, screenshot, and `test_sim` all passed on the same `iPhone 17 Pro` simulator.

## Cleanup / review gate

- AI slop cleanup scope was limited to the G002/G003 changed files.
- Cleanup finding: `MapScreen` pre-iOS fallback used `.regularMaterial`; changed to plain `.background.opacity(0.92)` + stroke to keep the non-glass fallback plain.
- Cleanup finding: route payload carried full `RecommendationCardModel`; changed to stable `cardID` and destination lookup to reduce navigation coupling.
- Code review lane: independent `code-reviewer` found only LOW/COMMENT items.
  - Visible English copy `Map-first discovery` was changed to `지도 우선 탐색`.
  - duplicated force-unwrapped Apple Maps URL construction was replaced with shared optional `RecommendationCardModel.appleMapsURL`.
- Architecture lane: `WATCH` risks were addressed by stable route IDs, shared category icon / Apple Maps helpers, preview-runtime documentation, and explicit visual-only theme rail copy.

## 리뷰 메모

- Liquid Glass 관련 코드는 availability/fallback helper로 유지했다.
- `.derivedData/`, `.omx/team/`, `.omx/ultragoal/`, `.lazyweb/`는 로컬 산출물/운영 상태라 `.gitignore`에 둔다.
- worker-3의 `.derivedData` 전용 커밋은 통합하지 않았다.

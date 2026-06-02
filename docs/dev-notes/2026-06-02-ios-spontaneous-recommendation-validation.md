# 2026-06-02 iOS 즉흥 추천 전환 검증 메모

## 범위

- 팀 작업: OMX `implement-pero-ios-ra-1d791323` Task 3.
- Ultragoal 참조: `.omx/ultragoal/goals.json`의 `G001-reframe-pero-from-search-theme-map-f`는 leader-owned 상태로 유지했다. 이 작업은 팀 증거와 문서/테스트만 추가하며 `.omx/ultragoal`은 변경하지 않는다.
- 검증 목표: iOS 앱이 검색/테마맵 선행 흐름이 아니라, 현재 위치 기반 “지금 바로 갈 만한 장소” 즉흥 추천 표면으로 시작하고 `/api/recommendations` 계약을 직접 사용한다는 점을 회귀 테스트와 XcodeBuildMCP 증거로 고정한다.

## 추가 회귀 체크

- `ios/PeroTests/NavigationModelTests.swift`
  - `viewModelRequestsRecommendationsFromCurrentLocation()`가 현재 위치 좌표, `themeId = "go-now"`, `radiusKm = 3`으로 추천 요청을 1회만 보내고 search 호출은 하지 않는지 확인한다.
  - `viewModelStartsAsSpontaneousRecommendationSurface()`가 초기 화면 상태를 추천 준비 상태(`.ready`, 카드 없음, “현재 위치 확인 전”)로 고정한다.
- `ios/PeroCore/Tests/PeroCoreTests/PeroAPIClientTests.swift`
  - `clientEncodesRecommendationRequestAndDecodesResponse()`가 base path를 보존한 `/api/recommendations` POST, JSON body(`themeId`, `latitude`, `longitude`, `radiusKm`), fallback/recommendation response decoding을 확인한다.
  - `previewProviderSuppliesOfflineMVPData()`가 preview provider의 `recommendations(_:)` 미리보기 추천 데이터도 제공하는지 확인한다.

## XcodeBuildMCP 검증

Session defaults는 worker worktree 기준으로 비영구 설정했다.

- Project: `/Users/ksj/Desktop/02_Work/Projects/Pero/.omx/team/implement-pero-ios-ra-1d791323/worktrees/worker-2/ios/Pero.xcodeproj`
- Scheme: `Pero`
- Configuration: `Debug`
- Simulator: `iPhone 17 Pro`, id `78867352-14AD-4092-BDF0-46DE89BD3A79`
- Bundle id: `com.pero.ios`
- Runtime env: `PERO_USE_PREVIEW=1`

결과:

- PASS: XcodeBuildMCP `build_sim`
  - status: `SUCCEEDED`
  - diagnostics: warnings `[]`, errors `[]`
  - log: `/Users/ksj/Library/Developer/XcodeBuildMCP/workspaces/worker-2-11c1a2ea459e/logs/build_sim_2026-06-02T12-58-51-529Z_pid94954_3f13f697.log`
- PASS: XcodeBuildMCP `test_sim(progress: true, testRunnerEnv: { PERO_USE_PREVIEW: "1" })`
  - status: `SUCCEEDED`
  - counts: passed `8`, failed `0`, skipped `0`
  - diagnostics: warnings `[]`, errors `[]`, testFailures `[]`
  - log: `/Users/ksj/Library/Developer/XcodeBuildMCP/workspaces/worker-2-11c1a2ea459e/logs/test_sim_2026-06-02T12-59-15-614Z_pid94954_99ed477d.log`
  - xcresult: `/Users/ksj/Library/Developer/XcodeBuildMCP/workspaces/worker-2-11c1a2ea459e/result-bundles/test_sim_2026-06-02T12-59-15-614Z_pid94954_cf7ba21f.xcresult`
- PASS: runtime UI after direct `simctl` install/launch fallback with `SIMCTL_CHILD_PERO_USE_PREVIEW=1`
  - launched: `com.pero.ios: 17574`
  - XcodeBuildMCP `wait_for_ui(textContains: "지금 바로 갈 만한 장소")` succeeded.
  - Snapshot also contained `현재 위치 37.5665, 126.9780`, `지도 우선 탐색`, `서울 반려 산책 공원`, `지도에서 확인`, `추천 이유 보기`.
  - screenshot: `/var/folders/6g/tr708wd138scfd24z7r293d00000gn/T/screenshot_optimized_62404094-24bb-4949-9d46-f20de840a015.jpg`

Caveat/recovery:

- XcodeBuildMCP `build_run_sim` timed out after 120s in this worker session, and a subsequent MCP `launch_app_sim` reported an inconsistent “not installed” state despite `install_app_sim` success. Recovery used the MCP-built app path, direct `xcrun simctl install/launch`, then MCP UI wait/screenshot. The runtime UI proof passed after recovery.

## Repository verification

- PASS: `swift test --package-path ios/PeroCore`
  - Swift Testing: `7` tests passed, `0` failed.
- PASS: lint fallback
  - `swift-format` is not installed; Swift build/test compiler diagnostics were used as the lint fallback.
- PASS: `git diff --check`
  - no whitespace errors.
- PASS: `IOS_TEST_DESTINATION='id=78867352-14AD-4092-BDF0-46DE89BD3A79' scripts/smoke_ios_core.sh`
  - Swift package manifest/build/test passed.
  - Xcode project list found targets `Pero`, `PeroTests` and schemes `Pero`, `PeroCore`.
  - Xcode simulator build passed with `** BUILD SUCCEEDED **`.
  - Xcode simulator tests passed with `** TEST SUCCEEDED **`; `NavigationModelTests` passed `8` cases.
  - Backend API/provider contract tests passed with Gradle `BUILD SUCCESSFUL`.
  - Final script output: `== PASS: Pero iOS MVP smoke ==`.

Caveat/recovery:

- An unpinned `scripts/smoke_ios_core.sh` run auto-selected simulator destination `id=C95BE98E-769F-4F0A-AA03-4094272FC886`; that `xcodebuild test` process was killed by the environment (`Killed: 9`). The rerun pinned to the already verified `iPhone 17 Pro` simulator id above and passed end-to-end.

## Final validation conclusion

The current iOS slice is verified as a spontaneous recommendation-first experience: app tests prove recommendation loading starts from current location without invoking search, core tests prove `/api/recommendations` encoding/decoding, XcodeBuildMCP proves clean simulator build/test plus preview UI text, and the full smoke script passes when pinned to the verified simulator.

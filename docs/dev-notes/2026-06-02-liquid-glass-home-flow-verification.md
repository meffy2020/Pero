# 2026-06-02 Liquid Glass 홈 추천 흐름 검증 메모

## 범위

- 대상 흐름: `ContentView` → `HomeRecommendationScreen` 추천 카드 → `PlaceExplanationDetailScreen` → `MapScreen` CTA 중, 사용자가 가장 먼저 보는 홈 추천 리스트를 Liquid Glass 1차 slice로 전환한다.
- 대상 프로젝트/스킴: `ios/Pero.xcodeproj`, scheme `Pero`.
- 대상 시뮬레이터: `iPhone 17 Pro` (`78867352-14AD-4092-BDF0-46DE89BD3A79`), iOS `26.5`.

## 사전 감사 결과

Liquid Glass로 전환할 표면:

- 홈 hero 카드: 현재 위치 기준 chip, “지금 바로 갈 만한 장소” 설명 묶음.
- fallback 안내 chip: 추천 반경 보완 안내.
- loading/error/empty 상태 메시지 카드.
- 추천 결과 `NavigationLink` row 카드: 실제 터치 가능한 고트래픽 진입점.

plain content로 유지할 표면:

- 추천 카드 내부의 제목/거리/이유/지역/카테고리 텍스트 자체는 별도 glass를 얹지 않고 가독성을 우선한다.
- 상세 화면과 지도 화면은 이번 slice에서 구조를 바꾸지 않는다. 다음 iteration에서 CTA/button 단위로 별도 감사한다.
- 의미 있는 morphing 전환이 없으므로 `glassEffectID`/`@Namespace`는 사용하지 않는다.
- 기존 custom blur stack은 추가하지 않는다.

## 구현 요약

변경 파일: `ios/Pero/Screens/DiscoverScreen.swift`

- `HomeRecommendationScreen.body`를 `recommendationGlassContainer`로 감싸고, iOS 26 이상에서 `GlassEffectContainer(spacing: 18)`를 사용한다.
- `homeRecommendationGlass(cornerRadius:tint:interactive:)` helper를 추가해 `#available(iOS 26, *)`로 native Liquid Glass와 이전 OS fallback을 분기한다.
- iOS 26 이상:
  - `Glass.regular.tint(...)`를 사용한다.
  - `glassEffect(..., in: .rect(cornerRadius: ...))`를 layout/padding 이후 적용한다.
  - `.interactive()`는 추천 카드 `NavigationLink` row처럼 실제 터치 가능한 control에만 적용한다.
- iOS 26 미만 fallback:
  - `.thinMaterial`/blur 계열이 아니라 `.background` + `.quaternary` stroke의 평범한 카드 표면으로 유지한다.

## 검증 명령과 결과

### 1. XcodeBuildMCP session defaults

확인/설정값:

- `projectPath`: `/Users/ksj/Desktop/02_Work/Projects/Pero/ios/Pero.xcodeproj`
- `scheme`: `Pero`
- `configuration`: `Debug`
- `simulatorName`: `iPhone 17 Pro`
- `simulatorId`: `78867352-14AD-4092-BDF0-46DE89BD3A79`
- `simulatorPlatform`: `iOS Simulator`
- `bundleId`: `com.pero.ios`
- runtime env: `PERO_USE_PREVIEW=1` for offline preview screenshot.

### 2. Build/run + screenshot

Worker lane에서 XcodeBuildMCP `build_run_sim`을 실행해 iOS 26.5 simulator build/install/launch를 PASS시켰다.

- Result: PASS
- Bundle id: `com.pero.ios`
- Screenshot while reaching target entry flow: `/var/folders/6g/tr708wd138scfd24z7r293d00000gn/T/screenshot_optimized_133a67ba-0d13-4f1b-9730-b5c0211c8c4c.jpg`

Leader 통합 후에는 같은 simulator에서 XcodeBuildMCP `launch_app_sim(env: { PERO_USE_PREVIEW: "1" })`와 `screenshot(returnFormat: "path")`로 Liquid Glass 홈 추천 화면을 다시 캡처했다.

- Launch: PASS, process `89861`
- Runtime log: `/Users/ksj/Library/Developer/XcodeBuildMCP/workspaces/Pero-51ba591fe951/logs/com.pero.ios_2026-06-02T10-23-09-043Z_helperpid89831_ownerpid5033_48e32332.log`
- Screenshot: `/var/folders/6g/tr708wd138scfd24z7r293d00000gn/T/screenshot_optimized_0ab4d980-b66e-4ae2-af52-206fc01e8f12.jpg`

### 3. Xcode scheme tests

```text
XcodeBuildMCP test_sim(progress: true, testRunnerEnv: { PERO_USE_PREVIEW: "1" })
```

결과: PASS

- Status: `SUCCEEDED`
- Counts: passed `6`, failed `0`, skipped `0`
- Diagnostics: warnings `[]`, errors `[]`, testFailures `[]`
- Test log: `/Users/ksj/Library/Developer/XcodeBuildMCP/workspaces/Pero-51ba591fe951/logs/test_sim_2026-06-02T10-18-55-613Z_pid5033_ad5a70e1.log`
- Result bundle: `/Users/ksj/Library/Developer/XcodeBuildMCP/workspaces/Pero-51ba591fe951/result-bundles/test_sim_2026-06-02T10-18-55-613Z_pid5033_d6ad9041.xcresult`

통과 테스트:

- `NavigationModelTests/recommendationStatesExposeKoreanCopy()`
- `NavigationModelTests/invalidRuntimeBaseURLIsNotPreviewFallback()`
- `NavigationModelTests/routesCarryStableRecommendationPayloads()`
- `NavigationModelTests/recommendationNormalizerPrefersCardsBeforeCourseStopsAndLimitsToThree()`
- `NavigationModelTests/viewModelRequestsRecommendationsFromCurrentLocation()`
- `NavigationModelTests/runtimeConfigurationUsesLiveProviderUnlessPreviewIsExplicit()`

### 4. Repository smoke script

```bash
scripts/smoke_ios_core.sh
```

결과: PASS

확인된 단계:

- `swift package --package-path ios/PeroCore dump-package` → PASS (`package=PeroCore targets=PeroCore,PeroCoreTests`)
- `swift build --package-path ios/PeroCore` → PASS (`Build complete!`)
- `swift test --package-path ios/PeroCore` → PASS (Swift Testing 6개 통과)
- Swift format lint → `swift-format` 미설치, compiler diagnostics fallback 사용
- `xcodebuild -list -project ios/Pero.xcodeproj` → PASS, schemes `Pero`, `PeroCore`
- `xcodebuild -project ios/Pero.xcodeproj -scheme Pero -destination 'generic/platform=iOS Simulator' build` → PASS (`** BUILD SUCCEEDED **`)
- `xcodebuild -project ios/Pero.xcodeproj -scheme Pero -destination "$IOS_TEST_DESTINATION" test` → PASS (`** TEST SUCCEEDED **`, `NavigationModelTests` 6개 통과)
- `backend/gradlew -p backend test` → PASS (`BUILD SUCCESSFUL`)

최종 출력: `== PASS: Pero iOS MVP smoke ==`

### 5. Diff hygiene

```bash
git diff --check
```

결과: PASS, whitespace error 없음.

## 남은 리스크

- pre-iOS 26 simulator는 이번 검증 환경에 포함하지 않았다. fallback은 `#available(iOS 26, *)` 컴파일 경로로 보호하고, iOS 26.5 SDK build/test로 문법과 타입 안정성은 확인했다.
- `.buttonStyle(.glass/.glassProminent)`는 이번 홈 추천 리스트에 독립 Button이 없어 적용하지 않았다. 상세/지도 CTA를 다음 Liquid Glass slice로 넘긴다.

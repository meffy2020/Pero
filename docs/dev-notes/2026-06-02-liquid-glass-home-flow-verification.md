# 2026-06-02 Liquid Glass 홈 추천 흐름 검증 메모

## 범위

- 대상 흐름: `ContentView` → `HomeRecommendationScreen` 추천 카드 → `PlaceExplanationDetailScreen` → `MapScreen` CTA.
- 대상 프로젝트/스킴: `ios/Pero.xcodeproj`, scheme `Pero`.
- 대상 시뮬레이터: `iPhone 17 Pro` (`78867352-14AD-4092-BDF0-46DE89BD3A79`), iOS `26.5`.
- 작업 lane: verification/docs. SwiftUI 구현 파일은 이 lane에서 수정하지 않고, 현재 worker-2 checkout 기준 검증 증거와 재검증 절차만 고정한다.

## Liquid Glass 통합 상태

현재 worker-2 checkout에서 아래 정적 검색을 수행했다.

```bash
rg -n "glassEffect|GlassEffect|buttonStyle\(\.glass|#available\(iOS 26" ios docs README.md scripts -S
```

확인 결과:

- `ios/Pero/Screens/DiscoverScreen.swift`
- `ios/Pero/Screens/PlaceholderDetailScreen.swift`
- `ios/Pero/Screens/MapScreen.swift`
- `ios/Pero/ContentView.swift`

위 파일들에는 아직 `glassEffect`, `GlassEffectContainer`, `.buttonStyle(.glass*)`, `#available(iOS 26, *)` Liquid Glass gating이 보이지 않는다. 따라서 이 메모의 빌드/스모크 결과는 “현재 통합된 checkout이 iOS 26.5에서 깨지지 않는다”는 baseline evidence이며, worker-1 구현 slice가 통합된 뒤 같은 명령으로 다시 확인해야 한다.

## 검증 명령과 결과

### 1. XcodeBuildMCP session defaults

설정값:

- `projectPath`: `ios/Pero.xcodeproj`
- `scheme`: `Pero`
- `configuration`: `Debug`
- `simulatorName`: `iPhone 17 Pro`
- `simulatorId`: `78867352-14AD-4092-BDF0-46DE89BD3A79`
- `simulatorPlatform`: `iOS Simulator`
- `derivedDataPath`: `.derivedData`

### 2. Build + run smoke

```text
XcodeBuildMCP build_run_sim(extraArgs: [], launchArgs: ["-PERO_USE_PREVIEW", "1"])
```

결과: PASS

- Status: `SUCCEEDED`
- Target: simulator
- Bundle id: `com.pero.ios`
- App path: `.derivedData/Build/Products/Debug-iphonesimulator/Pero.app`
- Build diagnostics: warnings `[]`, errors `[]`
- Build log: `/Users/ksj/Library/Developer/XcodeBuildMCP/workspaces/worker-2-e8f9201aff62/logs/build_run_sim_2026-06-02T10-09-42-195Z_pid69324_77d24c72.log`
- Runtime log: `/Users/ksj/Library/Developer/XcodeBuildMCP/workspaces/worker-2-e8f9201aff62/logs/com.pero.ios_2026-06-02T10-11-30-769Z_helperpid75069_ownerpid69324_7b4009ae.log`
- Screenshot: `/var/folders/6g/tr708wd138scfd24z7r293d00000gn/T/screenshot_optimized_133a67ba-0d13-4f1b-9730-b5c0211c8c4c.jpg`

Screenshot observation: app launched on the home recommendation flow and presented the iOS location permission dialog over the `Pero` home screen. This proves the app reaches the target entry flow on iOS 26.5; it does not yet prove post-permission Liquid Glass visual acceptance.

### 3. Xcode scheme tests

```text
XcodeBuildMCP test_sim(progress: true, testRunnerEnv: { PERO_USE_PREVIEW: "1" })
```

결과: PASS

- Status: `SUCCEEDED`
- Counts: passed `6`, failed `0`, skipped `0`
- Diagnostics: warnings `[]`, errors `[]`, testFailures `[]`
- Test log: `/Users/ksj/Library/Developer/XcodeBuildMCP/workspaces/worker-2-e8f9201aff62/logs/test_sim_2026-06-02T10-11-52-039Z_pid69324_e95a2fb1.log`
- Result bundle: `/Users/ksj/Library/Developer/XcodeBuildMCP/workspaces/worker-2-e8f9201aff62/result-bundles/test_sim_2026-06-02T10-11-52-040Z_pid69324_36222cd2.xcresult`

통과 테스트:

- `NavigationModelTests/recommendationStatesExposeKoreanCopy()`
- `NavigationModelTests/invalidRuntimeBaseURLIsNotPreviewFallback()`
- `NavigationModelTests/routesCarryStableRecommendationPayloads()`
- `NavigationModelTests/recommendationNormalizerPrefersCardsBeforeCourseStopsAndLimitsToThree()`
- `NavigationModelTests/viewModelRequestsRecommendationsFromCurrentLocation()`
- `NavigationModelTests/runtimeConfigurationUsesLiveProviderUnlessPreviewIsExplicit()`

### 4. Repository smoke script

```bash
IOS_TEST_DESTINATION='id=78867352-14AD-4092-BDF0-46DE89BD3A79' scripts/smoke_ios_core.sh
```

결과: PASS

확인된 단계:

- `swift package --package-path ios/PeroCore dump-package` → PASS (`package=PeroCore targets=PeroCore,PeroCoreTests`)
- `swift build --package-path ios/PeroCore` → PASS (`Build complete!`)
- `swift test --package-path ios/PeroCore` → PASS (Swift Testing 6개 통과)
- Swift format lint → `swift-format` 미설치, compiler diagnostics fallback 사용
- `xcodebuild -list -project ios/Pero.xcodeproj` → PASS, schemes `Pero`, `PeroCore`
- `xcodebuild -project ios/Pero.xcodeproj -scheme Pero -destination 'generic/platform=iOS Simulator' build` → PASS (`** BUILD SUCCEEDED **`)
- `xcodebuild -project ios/Pero.xcodeproj -scheme Pero -destination id=78867352-14AD-4092-BDF0-46DE89BD3A79 test` → PASS (`** TEST SUCCEEDED **`, `NavigationModelTests` 6개 통과)
- `backend/gradlew -p backend test` → PASS (`BUILD SUCCESSFUL in 49s`)

최종 출력: `== PASS: Pero iOS MVP smoke ==`

## Liquid Glass 통합 후 재검증 체크리스트

구현 slice가 통합되면 아래를 다시 확인한다.

1. `DiscoverScreen.swift`, `PlaceholderDetailScreen.swift`, `MapScreen.swift`의 glass 적용이 `#available(iOS 26, *)` fallback을 가진다.
2. native API만 사용한다: `glassEffect`, `GlassEffectContainer`, `.buttonStyle(.glass)`, `.buttonStyle(.glassProminent)`.
3. `interactive()`는 NavigationLink/Button 등 터치 가능한 control에만 적용한다.
4. content-heavy 텍스트 영역은 plain/readable 상태를 유지한다.
5. custom blur stack 또는 의미 없는 `glassEffectID`/morphing을 추가하지 않는다.
6. 위 Build + run, Xcode tests, `scripts/smoke_ios_core.sh`를 같은 simulator에서 다시 PASS시킨다.

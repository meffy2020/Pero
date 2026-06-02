# 2026-06-02 iOS Native MVP 검증/시연 메모

## 배경

Pero iOS 네이티브 MVP는 기존 Spring Boot 검색 API 계약을 직접 외부 관광 API 호출 없이 소비하고, 사용자에게 “지금 갈 만한 장소”를 설명 우선으로 추천해야 한다. 이번 메모는 앱 shell(`ios/Pero.xcodeproj`)과 코어 계층(`ios/PeroCore`)을 함께 반복 검증하기 위한 smoke command와 현재 증거를 고정한다.

## 이번 변경

- `ios/Pero.xcodeproj` 아래 SwiftUI 앱 shell을 추가하고 홈/추천/상세/지도 확인 흐름을 한국어 시연 상태로 구성했다.
- `ios/PeroCore` Swift Package를 검증 대상으로 분리했다.
- `PeroAPIProviding` 프로토콜과 `HTTPTransport` seam을 기준으로 live client와 preview provider를 구분한다.
- 앱 런타임은 기본적으로 `PERO_API_BASE_URL` 또는 `http://127.0.0.1:8080` live backend provider를 사용하고, `PERO_USE_PREVIEW=1`일 때만 preview provider를 명시적으로 사용한다.
- SwiftUI preview/test는 preview provider와 고정 위치 provider를 주입해 오프라인 시연 상태를 만들 수 있고, live client는 백엔드 `/api/*` 계약만 호출한다.
- 홈 화면의 추천 요청은 `CoreLocation` 현재 위치 provider에서 받은 좌표를 `RecommendationRequest`에 넣는다.
- SwiftPM 산출물은 source artifact가 아니므로 `**/.build/`를 ignore한다.

## 실행/검증

반복 smoke는 저장소 루트에서 아래 한 줄로 실행한다.

```bash
scripts/smoke_ios_core.sh
```

스크립트가 실행하는 검증 범위:

1. `swift package --package-path ios/PeroCore dump-package`
2. `swift build --package-path ios/PeroCore`
3. `swift test --package-path ios/PeroCore`
4. `swift-format lint --recursive ios/PeroCore/Sources ios/PeroCore/Tests` 또는 미설치 시 Swift compiler diagnostics fallback
5. `backend/gradlew` 실행 가능 여부를 확인하고, 불가능하면 smoke를 실패 처리
6. `xcodebuild -list -project ios/Pero.xcodeproj`
7. `xcodebuild -project ios/Pero.xcodeproj -scheme Pero -destination 'generic/platform=iOS Simulator' build`
8. `IOS_TEST_DESTINATION`이 없으면 `xcodebuild -showdestinations`에서 사용 가능한 iOS Simulator `id=...`를 자동 선택
9. `xcodebuild -project ios/Pero.xcodeproj -scheme Pero -destination "$IOS_TEST_DESTINATION" test`
10. `backend/gradlew -p backend test`

기본 simulator test destination은 현재 Xcode가 노출하는 첫 번째 사용 가능 iOS Simulator `id=...`를 자동 선택하며, 필요하면 `IOS_TEST_DESTINATION` 환경 변수로 바꾼다.

현재 확인한 증거:

- `swift test --package-path ios/PeroCore` → PASS, Swift Testing 6개 통과
- `swift build --package-path ios/PeroCore` → PASS, `Build complete!`
- Swift lint → `swift-format` 미설치, build/test compiler diagnostics 기준 경고 없이 PASS
- `xcodebuild -list -project ios/Pero.xcodeproj` → PASS, scheme `Pero` 확인
- `xcodebuild -project ios/Pero.xcodeproj -scheme Pero -destination 'generic/platform=iOS Simulator' build` → PASS, `BUILD SUCCEEDED`
- `xcodebuild -project ios/Pero.xcodeproj -scheme Pero -destination "$IOS_TEST_DESTINATION" test` → PASS, `NavigationModelTests` 6개 통과
- `backend/gradlew -p backend test` → PASS, `BUILD SUCCESSFUL`

## 데모 체크포인트

- Preview/offline 데모: `PERO_USE_PREVIEW=1` 또는 `PeroAPIProviderFactory.preview()` 테스트 주입으로 백엔드 없이 추천/상세/지도 상태를 보여줄 수 있다.
- Live/API 데모: 기본 런타임은 `PERO_API_BASE_URL` 또는 `http://127.0.0.1:8080`을 통해 `PeroAPIProviderFactory.live(baseURL:)`를 사용하고 백엔드 `/api/*` 계약을 확인한다.
- 위치 데모: 앱 런타임은 `CoreLocation` 현재 위치를 요청한다. Simulator에서는 Features > Location에서 위치를 지정하거나 테스트에서는 `StaticLocationProvider`를 주입한다.
- 앱 화면은 설명 우선 MVP 원칙에 맞춰 추천 이유, 현재 이용 가능성, 거리/좌표, 지도 확인 CTA를 먼저 드러낸다.
- 로그인, 개인화, 자연어 검색 고도화, iOS 직접 외부 관광 API 호출은 이번 MVP 범위 밖으로 유지한다.

## 영향 파일

- `.gitignore`
- `ios/Pero.xcodeproj/*`
- `ios/Pero/*`
- `ios/PeroTests/*`
- `ios/PeroCore/Package.swift`
- `ios/PeroCore/Sources/PeroCore/API/*`
- `ios/PeroCore/Sources/PeroCore/Models/*`
- `ios/PeroCore/Tests/PeroCoreTests/*`
- `scripts/smoke_ios_core.sh`
- `docs/dev-notes/2026-06-02-ios-native-mvp-verification.md`

## 커밋/PR

- Team 산출물은 `ultragoal-g001-implem-1d791323`에서 병합했다.
- 앱과 Core는 최종적으로 소문자 `ios/` 경로 아래에 통합했다.

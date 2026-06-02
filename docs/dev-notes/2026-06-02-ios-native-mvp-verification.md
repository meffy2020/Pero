# 2026-06-02 iOS Native MVP 검증/시연 메모

## 배경

Pero iOS 네이티브 MVP는 기존 Spring Boot 검색 API 계약을 직접 외부 관광 API 호출 없이 소비해야 한다. 이번 메모는 iOS 코어 계층(`ios/PeroCore`)의 모델/API 어댑터/provider seam을 반복 검증하기 위한 smoke command와 현재 증거를 고정한다.

## 이번 변경

- `ios/PeroCore` Swift Package를 검증 대상으로 분리했다.
- `PeroAPIProviding` 프로토콜과 `HTTPTransport` seam을 기준으로 live client와 preview provider를 구분한다.
- SwiftUI 화면은 preview provider로 오프라인 시연 상태를 만들 수 있고, live client는 백엔드 `/api/*` 계약만 호출한다.
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
5. `backend/gradlew -p backend test`

현재 확인한 증거:

- `swift test --package-path ios/PeroCore` → PASS, Swift Testing 5개 통과
- `swift build --package-path ios/PeroCore` → PASS, `Build complete!`
- Swift lint → `swift-format` 미설치, build/test compiler diagnostics 기준 경고 없이 PASS
- `backend/gradlew -p backend test` → PASS, `BUILD SUCCESSFUL`

## 데모 체크포인트

- Preview/offline 데모: `PeroAPIProviderFactory.preview()`를 주입하면 백엔드 없이 장소/검색 기본 상태를 보여줄 수 있다.
- Live/API 데모: `PeroAPIProviderFactory.live(baseURL:)`를 주입하고 백엔드 `/api/health`, `/api/search`, `/api/places` 계약을 확인한다.
- iOS 앱 shell 또는 화면 구현 작업자가 `PeroAPIProviding`만 의존하면 mock/live provider 전환이 가능하다.

## 영향 파일

- `.gitignore`
- `ios/PeroCore/Package.swift`
- `ios/PeroCore/Sources/PeroCore/API/*`
- `ios/PeroCore/Sources/PeroCore/Models/*`
- `ios/PeroCore/Tests/PeroCoreTests/*`
- `scripts/smoke_ios_core.sh`
- `docs/dev-notes/2026-06-02-ios-native-mvp-verification.md`

## 후속 작업

- Xcode app shell/navigation(Task 1)과 UI screens(Task 3)가 병합되면 동일 smoke 후 `xcodebuild test` 또는 simulator smoke를 추가한다.
- 앱 통합 후에는 preview provider 화면 상태와 live backend happy path를 각각 캡처해 최종 데모 증거에 첨부한다.
- 로그인, 개인화, 자연어 검색 고도화, iOS 직접 외부 관광 API 호출은 이번 MVP 범위 밖으로 유지한다.

## 커밋/PR

- Task 2 완료 커밋: `5c05f4e task: stabilize iOS API seams`
- 이 메모와 smoke script는 Task 4 검증/데모 증거 산출물이다.

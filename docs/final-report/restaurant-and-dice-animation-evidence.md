# 식당 후보 확장 및 주사위 뽑기 애니메이션 검증

검증 시각: 2026-06-10 01:13 KST

## 식당 후보 수

식당 모드는 `mode=restaurant&source=kakaoLocal` 기준으로 카카오 로컬 캐시만 사용한다.
가짜 더미/카페 후보는 사용하지 않는다.

- 하계동 좁은 지도 bounds: 128개
- 노원구 넓은 지도 bounds: 284개
- 노원/상계/중계/공릉 bounds: 284개

검증 쿼리 공통값:

```text
/api/places?mode=restaurant&source=kakaoLocal&limit=500&density=low&zoom=8
```

확인 내용:

- `randomScope`: `현재 지도 안 후보 · mode=restaurant · source=kakaoLocal · N개`
- `fallbackUsed`: `false`
- `낮은 줌 마커 제한`: 응답에 포함되지 않음
- 카페 카테고리: 0건

## 앱 동작

- iPhone 실기기 빌드 성공
- iPhone 실기기 설치 성공: `com.pero.ios`
- iPhone 실기기 실행 성공: PID `9378`
- 시뮬레이터 최신 화면 캡처:
  - `docs/final-report/screenshots/pero-ios-dice-animation-ready.png`
  - `docs/final-report/screenshots/pero-ios-dice-animation-ready-2.png`

## 애니메이션 변경

뽑기 버튼을 누르면 지도 위에서 주사위가 빠르게 튕기며 이동하고, 벽 충돌 시 지도 캔버스가 짧게 흔들린다.
최종 단계에서는 주사위가 뽑힌 장소 좌표 근처로 착지한 뒤, 카메라가 해당 장소 중심으로 이동한다.

구현 요소:

- 주사위 토큰 + 핍 직접 렌더링
- 이동 잔상/모션 블러
- 모서리 충돌 시 지도 흔들림
- 착지/확정 햅틱
- 시스템 사운드 기반 tick/reveal 효과
- Reduce Motion 환경에서는 짧은 착지 애니메이션으로 축약

## 2026-06-10 마커/주사위 에셋 교체

사용자 제공 주사위 이미지를 앱용 투명 PNG 에셋으로 변환했다.

- 앱 에셋: `ios/Pero/Assets.xcassets/pero-dice-marker.imageset/pero-dice-marker.png`
- 지도 선택 마커: 모든 장소/식당/축제 카테고리에서 같은 주사위 에셋 사용
- 뽑기 애니메이션 주사위: 같은 에셋 사용
- 뽑기 중 상단 상태 카드: 어두운 글라스 대신 흰색 반투명 애플 글라스 톤으로 조정
- 시뮬레이터 캡처: `docs/final-report/screenshots/pero-ios-dice-marker-glass-ready.png`

검증:

- `xcodebuild -project ios/Pero.xcodeproj -scheme Pero -destination 'platform=iOS Simulator,id=78867352-14AD-4092-BDF0-46DE89BD3A79' build` 성공
- iPhone 실기기 빌드/설치 성공
- iPhone 실기기 실행은 기기 잠금 상태로 iOS가 차단

## 2026-06-10 중복 없는 상태별 스크린샷 검증

기존 캡처가 같은 기본 화면만 반복되는 문제를 수정했다.
`DEBUG` 빌드에서만 `PERO_SCREENSHOT_SCENARIO` 환경변수로 캡처 상태를 강제할 수 있게 했다.
운영 일반 실행에서는 해당 경로가 동작하지 않는다.
최종 검증 세트는 fixture/dummy 카드를 사용하지 않고, 로컬 백엔드의 실제 캐시 응답을 로드한 뒤 선택 상태를 만든다.

최종 상태별 캡처 파일:

- `docs/final-report/screenshots/varied/verified-20260610/pero-home-ready.png`
- `docs/final-report/screenshots/varied/verified-20260610/pero-dice-moving.png`
- `docs/final-report/screenshots/varied/verified-20260610/pero-restaurant-result.png`
- `docs/final-report/screenshots/varied/verified-20260610/pero-festival-result.png`
- `docs/final-report/screenshots/varied/verified-20260610/pero-attraction-result.png`
- `docs/final-report/screenshots/varied/verified-20260610/pero-verified-contact-sheet.png`

최종 해시 검증:

```text
4fe895953264fc5c05b6e30b7b17bb259ce71ce4  pero-attraction-result.png
597a24d6a5500dd3307ad2aab4aed7df3acb9e63  pero-dice-moving.png
8368c252aef5379d77049b6691965e95736dfb3b  pero-festival-result.png
e3257ff70fe24600988fa610e75715b91eaeeb0c  pero-home-ready.png
294fce62f6d68a3958aa8e3c45e8682322f05f5c  pero-restaurant-result.png
2ea0b485921e451e195a3c3139732c947148aaa0  pero-verified-contact-sheet.png
```

최종 결과:

- 5개 상태 캡처의 SHA-1이 모두 다르다.
- contact sheet로 육안 검수했다.
- 식당 결과는 `kakaoLocal` 실제 캐시 장소 `부뚜막`이다.
- 축제 결과는 실제 축제 캐시 `서울어텀페스타`다.
- 장소 결과는 실제 장소 캐시 `군기시유적전시실`이다.
- `ContentView` 기본 자동 로드는 DEBUG 캡처 시나리오에서만 비활성화해 캡처 상태가 기본 화면으로 덮이지 않게 했다.

이전 캡처 파일은 아래 기록처럼 남겨두되, 최종 보고서에는 `verified-20260610` 세트를 사용한다.

상태별 캡처 파일:

- `docs/final-report/screenshots/varied-v2/pero-restaurant-ready.png`
- `docs/final-report/screenshots/varied-v2/pero-restaurant-dice.png`
- `docs/final-report/screenshots/varied-v2/pero-restaurant-result.png`
- `docs/final-report/screenshots/varied-v2/pero-festival-result.png`
- `docs/final-report/screenshots/varied-v2/pero-place-result.png`
- `docs/final-report/screenshots/varied-v2/pero-varied-v2-contact-sheet.png`

해시 검증:

```text
restaurant-ready ae7fd112bfcad0c6763919314376c7f61f445c4d0a273987d7aef5c129edc093
restaurant-dice 5beab2c8b32bd8c40f04d9936f6fc177c9a81d748dc14608f41243def9b40495
restaurant-result b95cb568b734b3e7332a22f5511c804549a1d2135881bce2e1ea701b8330c796
festival-result 2ce685efc28fb62de334f592eedc66857b0b375dfdc190aab5d8bc185da971ca
place-result 75e03e387d535983e946f309bc3ea4b655944a8702bf08bd39d7dac1d7b2325b
```

결과: 5개 중 5개 고유 해시. 같은 화면 반복 아님.

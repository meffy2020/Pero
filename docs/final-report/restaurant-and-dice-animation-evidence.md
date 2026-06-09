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

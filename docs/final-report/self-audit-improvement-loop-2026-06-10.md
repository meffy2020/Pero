# 2026-06-10 자율 감사/개선 루프

## 발견한 문제

- `kakaoLocal` 캐시 안에 `더미 광화문본점` 레코드가 남아 있었다.
- 식당 뽑기는 실제 서비스 기준으로 카카오 로컬 캐시 식당만 내려가야 하므로, 이름/힌트에 synthetic 표식이 있는 후보는 런타임에서도 차단되어야 한다.
- 기존 provider 통합 테스트 일부는 `kakaoLocal` 기본 활성화 이후에도 특정 provider만 검증한다고 가정해 전체 테스트에서 불안정했다.

## 적용한 개선

- `KakaoLocalPlaceDataProvider`에서 synthetic 후보를 로딩 단계에서 필터링한다.
  - 차단 표식: `더미`, `dummy`, `fake`, `mock`, `시뮬레이션`, `simulation`
- `scripts/etl/kakao_places_to_pero.py`에서도 같은 표식이 이름/summary/searchHints에 있는 카카오 장소는 캐시에 쓰지 않도록 했다.
- 기존 `backend/src/main/resources/data/places.kakao.json`에서 `더미 광화문본점` 1건을 제거했다.
- `places.kakao.json.meta.json`의 count를 `2163`으로 갱신했다.
- 회귀 테스트 `SearchControllerKakaoQualityIntegrationTests`를 추가해 synthetic 식당이 `/api/places`에 내려오지 않도록 잠갔다.
- provider별 통합 테스트에는 `kakaoLocal.enabled=false`를 명시해 테스트 의도를 고정했다.

## 검증

- `cd backend && ./gradlew test --tests com.pero.search.controller.SearchControllerKakaoQualityIntegrationTests` 성공
- `cd backend && ./gradlew test` 성공
- `python3 -m py_compile scripts/etl/kakao_places_to_pero.py` 성공
- production 카카오 캐시 검사 결과: `places_kakao_count=2163`, `synthetic_hits=0`
- `xcodebuild -project ios/Pero.xcodeproj -scheme Pero -destination 'platform=iOS Simulator,id=78867352-14AD-4092-BDF0-46DE89BD3A79' build` 성공

## 다음 루프에서 보면 좋은 점

1. 축제 캐시도 제목/일정 기준 품질 게이트를 ETL 산출물 검사로 고정한다.
2. 식당 캐시 갱신 후 행정동별 후보 수 리포트를 자동 생성한다.
3. iOS 결과 카드에서 source/debug 문구는 보고서/디버그에는 남기되, 일반 사용자 화면에서는 더 자연스러운 라벨로 줄인다.
4. 실기기 잠금 해제 상태에서 카카오 공유 메시지 캡처까지 보고서 증거로 추가한다.

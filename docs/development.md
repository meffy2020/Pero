# Pero 개발 통합 문서

## 서비스 한 줄

- `Pero`는 관광지 중심 추천 테마맵 서비스임.

## 현재 제품 정의

- 기본 경험은 `테마 선택 -> 지도 탐색 -> 장소 상세 해석`임.
- 검색은 보조 탐색 기능으로 유지함.
- 대시보드형 검색 제품으로 보이지 않도록 단순화함.
- 서울 특화 데이터와 전국 fallback 구조를 명확하게 드러냄.

## 데이터 전략

- 서울권은 `스마트서울맵`의 주소/배경지도/도시생활 테마를 우선 활용함.
- 전국 관광 데이터의 기본 소스는 `한국관광공사 TourAPI`로 고정함.
- 외부 API는 프런트에서 직접 호출하지 않음.
- 프런트는 백엔드 ETL/캐시 뒤의 응답만 사용함.

## 프런트 구조

- 프런트는 command center 셸을 제거하고 단순한 테마맵 구조로 변경함.
- 기본 화면 구성:
  - 서비스 정의와 데이터 전략을 설명하는 hero
  - 테마 선택 영역
  - 지도 중심 탐색 영역
  - 장소 상세 해석 패널
- 검색 입력은 지도 갱신용 보조 UI로 배치함.

## 백엔드 계약

- 현재 사용 API:
  - `GET /api/places`
  - `POST /api/search`
- `POST /api/recommendations`
- `GET /api/events`
- 상세 JSON 규약은 `docs/api-contract.md`를 기준으로 함.
- iOS 지도 후보 풀은 `/api/places?latitude={lat}&longitude={lng}&limit=360&includeTourApi=false`를 사용함.
- 외부 관광 데이터 호출은 계속 백엔드 뒤에 숨김.

## 지도와 상호작용

- 지도 엔진은 계속 `Leaflet` 사용함.
- 지도는 메인 탐색 영역으로 유지함.
- 상호작용:
  - 테마 선택 -> 지도 결과 갱신
  - 카드 hover -> 지도 하이라이트
  - 카드 click -> 지도 focus + 상세 패널 교체
  - 마커 click -> 선택 장소 동기화

## 데이터와 메타데이터

- 현재 결과 상세는 `tourApi` 메타데이터를 사용함.
- 프런트는 `tourApi`를 이용해 운영 정보, 이미지, 반려동물 정보 등을 상세 패널에서 해석함.
- 없는 필드는 빈 상태로 나열하지 않고 숨김 처리하는 방향을 유지함.

## 디자인 기준

- 목표 인상은 `관광 테마 큐레이션 서비스`임.
- 제거한 것:
  - command-center 레이아웃
  - 좌측 탭 셸
  - event strip
  - compare/data intel 보드
  - 과한 상태 표시
- 유지한 것:
  - 지도 중심 탐색
  - 선택 장소 해석 패널
  - 마커/카드 동기화

## 실행 방법

### 백엔드

```bash
cd backend
./gradlew bootRun
```

### 프런트

```bash
cd frontend
npm run dev
```

- 프런트 주소: `http://localhost:3000`
- 프런트 `/api` 요청은 백엔드 `8080`으로 rewrite됨.

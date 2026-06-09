# Pero 개발 통합 문서

## 서비스 한 줄

- `Pero`는 현재 위치와 지도 화면을 기준으로 근처 후보를 좁히고, 캐시 데이터에서 랜덤 추천을 제공하는 관광 테마맵 서비스다.

## 현재 제품 정의

- 기본 경험은 `현재 위치/지도 -> 후보 제한 -> 랜덤 추천 -> 상세 확인`이다.
- 검색은 보조 탐색 기능으로 유지한다.
- 대시보드형 검색 제품으로 보이지 않도록 단순화한다.
- 서울 특화 데이터와 전국 fallback 구조를 명확하게 드러낸다.

## 데이터 전략

- 외부 API는 앱/웹/백엔드 요청 경로에서 실시간 호출하지 않는다.
- 한국관광공사, 스마트서울맵, 카카오는 ETL 캐시 소스로만 다룬다.
- 서울권은 `스마트서울맵`의 주소/배경지도/도시생활 테마를 우선 활용한다.
- 전국 관광 데이터의 기본 소스는 `한국관광공사 TourAPI`로 고정한다.
- 카페 모드는 캐시에 있는 카페 후보가 있을 때만 제공한다.
- 요청 시점에는 서버 시작 시 만든 지역/카테고리/source/진행중 축제 인덱스를 사용한다.

## 프런트/iOS 구조

- 웹 프런트는 command center 셸을 제거하고 단순한 테마맵 구조로 유지한다.
- iOS는 세로형 지도-first 흐름을 기준으로 한다.
- iOS 랜덤 요청 흐름:
  - 현재 위치 또는 지도 중심 좌표를 보낸다.
  - 현재 지도 bounds를 보낸다.
  - 카메라 줌/레벨로 `density`를 결정한다.
  - 선택 모드를 `mode/category`로 매핑한다.
  - 최근 추천된 `placeId`를 요청에만 포함해 즉시 반복을 줄인다.
  - `includeTourApi=false`로 지도/랜덤 payload를 가볍게 유지한다.
- 현재 iOS 모드 preset:
  - 관광/장소: `mode=tour`, `category=관광지`
  - 카페/식당: `mode=cafe`, `category=카페`
  - 축제: `mode=festival`, `category=행사/공연/축제`
- 백엔드는 산책/문화 같은 semantic mode를 추가로 처리할 수 있으나, 현재 화면 preset은 위 세 가지로 제한한다.

## 백엔드 계약

- 현재 사용 API:
  - `GET /api/places`
  - `POST /api/recommendations`
  - `POST /api/search`
  - `GET /api/events`
- 상세 JSON 규약은 `docs/api-contract.md`를 기준으로 한다.
- 지도 후보 풀은 화면/위치 기준으로 제한한다.
- `/api/places`는 `latitude`, `longitude`, `north`, `south`, `east`, `west`, `radiusKm`, `zoom`, `density`, `category`, `mode`, `limit`, `includeTourApi`를 받는다.
- `/api/recommendations`는 같은 지도 상태와 `recentPlaceIds`를 받아 모드 후보군을 먼저 만든 뒤 랜덤을 수행한다.
- 응답 `source`, `generatedAt`, `fallbackUsed`, `randomScope`를 내려 UX와 디버깅에서 같은 상태를 볼 수 있게 한다. 응답 `source`는 요청 필터가 아니라 캐시 provenance 메타다.
- 서버는 사용자별 추천 이력을 저장하지 않는다.

## 지도와 상호작용

- 지도 엔진은 계속 `Leaflet` 사용한다.
- 지도는 메인 탐색 영역으로 유지한다.
- 상호작용:
  - 테마 선택 -> 지도 결과 갱신
  - 지도 이동/확대 -> 현재 bounds 기준 후보 갱신
  - 낮은 줌 -> 개별 마커 다량 표시 대신 요약/클러스터 후보만 표시
  - 카드 hover -> 지도 하이라이트
  - 카드 click -> 지도 focus + 상세 패널 교체
  - 마커 click -> 선택 장소 동기화

## 데이터와 메타데이터

- 지도/랜덤 응답은 상세 payload를 싣지 않는다.
- `tourApi` 상세 원문, 이미지, 홈페이지, 긴 설명은 상세 화면에서 필요할 때만 사용한다.
- 없는 필드는 빈 상태로 나열하지 않고 숨긴다.
- `fallbackUsed=true`이면 사용자가 이해할 수 있는 짧은 상태 문구를 `randomScope` 기반으로 보여준다.

## 디자인 기준

- 목표 인상은 `관광 테마 큐레이션 서비스`다.
- 문구는 짧고 공간 기준으로 쓴다. 예: `현재 지도 안 장소`, `후보 부족으로 서울 전체 확장`.
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
- 프런트 `/api` 요청은 백엔드 `8080`으로 rewrite된다.

### 테스트

```bash
cd backend
./gradlew cleanTest test

cd ios/PeroCore
swift test
```

Xcode 시뮬레이터 검증은 `Pero` scheme, `iPhone 17 Pro` 시뮬레이터 기준으로 수행한다.

# Pero API Contract

## 공통 원칙

- 앱, 웹, 백엔드 요청 경로는 한국관광공사, 스마트서울맵, 카카오 같은 외부 API를 실시간 호출하지 않는다.
- 외부 데이터는 ETL로 만든 캐시만 사용한다. 요청 시점에는 캐시 데이터와 서버 시작 시 만든 인덱스만 조회한다.
- 지도/랜덤 응답은 가벼운 목록 응답이다.
- 기본 필드는 `id`, `name`, `category`, `latitude`, `longitude`, `summary`, `sourceAttribution` 중심이다.
- 이미지, 홈페이지, 긴 설명, TourAPI 상세 원문은 상세 화면이나 명시적 상세 용도에서만 다룬다.
- `category`는 캐시 장소 분류다. iOS 뽑기 모드와 같은 값으로 취급하지 않는다.
- `source`, `generatedAt`, `fallbackUsed`, `randomScope`는 추천/지도 결과의 데이터 상태를 설명한다.
- `total`은 현재 응답에 포함된 배열 개수다. 전체 캐시 개수는 `source.count`에서 확인한다.

## 모드와 카테고리 매핑

현재 iOS 클라이언트 preset은 아래 세 가지다. 백엔드는 `walk`, `culture` 같은 semantic mode도 처리할 수 있으므로, 표는 전체 enum이 아니라 현재 화면 진입점 기준이다.

| 화면 모드 | API `mode` | API `category` | 정책 |
| --- | --- | --- | --- |
| 관광/장소 | `tour` | `관광지` | 관광지 후보군을 먼저 만든 뒤 위치/지도 조건을 적용한다. |
| 카페/식당 | `cafe` | `카페` | 캐시에 있는 카페 후보만 사용한다. 카카오 실시간 호출은 하지 않는다. |
| 축제 | `festival` | `행사/공연/축제` | 진행중 축제 인덱스와 캐시 일정 정보를 우선 사용한다. |

## `GET /api/places`

지도 화면에 필요한 후보만 받는다.

Query:

- `latitude`, `longitude`: 선택. 현재 위치 또는 지도 중심 좌표. 둘 다 있을 때 중심 좌표 필터에 사용한다.
- `radiusKm`: 선택. 중심 좌표 기준 반경.
- `north`, `south`, `east`, `west`: 선택. 현재 지도 bounds. 네 값이 모두 있을 때 지도 화면 안 후보로 제한한다.
- `zoom`: 선택. 지도 줌/레벨 판단 값.
- `density`: 선택. `summary`면 낮은 밀도 응답으로 처리한다.
- `category`: 선택. 캐시 장소 카테고리.
- `mode`: 선택. `tour`, `cafe`, `festival` 등 추천 모드.
- `source`: 선택. `smartSeoul`, `koreaTour` 같은 요청 필터. 응답의 `source` 메타 객체와 이름은 같지만 의미는 다르다.
- `activeFestival`: 선택. 진행중 축제 여부.
- `limit`: 선택. 최대 응답 개수. 서버에서 상한 처리한다.
- `includeTourApi`: 선택. wire 기본값은 기존 호환을 위해 `true`다. 지도/랜덤 클라이언트는 반드시 `false`를 보내 상세 원문 payload를 제외한다.

Response:

응답의 `source`는 실제 사용한 캐시 공급자 메타데이터다. 요청 필터 `source`와 같은 필드명을 쓰지만, 응답에서는 provenance 설명으로만 읽는다.

```json
{
  "source": {
    "providerId": "koreaTour",
    "providerName": "한국관광공사 TourAPI",
    "status": "ok",
    "generatedAt": "2026-06-09T00:00:00+09:00",
    "count": 10526
  },
  "generatedAt": "2026-06-09T06:45:00+09:00",
  "fallbackUsed": false,
  "randomScope": "현재 지도 안 후보",
  "total": 1,
  "places": [
    {
      "id": "koreaTour-984588",
      "name": "아이닥안경",
      "category": "쇼핑",
      "district": "서울 중구",
      "address": "서울특별시 중구 명동3길 6",
      "roadAddress": "서울특별시 중구 명동3길 6",
      "summary": "서울 중구 권역의 쇼핑 유형 후보입니다.",
      "tags": ["서울 중구", "쇼핑", "실내"],
      "themeTags": ["서울", "가족나들이"],
      "latitude": 37.5637,
      "longitude": 126.9826,
      "sourceAttribution": "한국관광공사 TourAPI",
      "tourApi": null
    }
  ]
}
```

낮은 줌 정책:

- `density=summary` 또는 낮은 줌으로 판단되는 요청은 개별 마커를 많이 내려주지 않는다.
- 이 단계의 응답은 클러스터/지역 요약 UI를 위한 작은 후보군으로 제한한다.
- 상세 마커와 상세 정보는 확대 또는 상세 화면 진입 후 별도 흐름에서 다룬다.

기본 iOS 지도 후보 요청:

```text
GET /api/places?latitude={lat}&longitude={lng}
  &north={n}&south={s}&east={e}&west={w}
  &zoom={zoom}&density={summary|detail}
  &category={category}&mode={mode}
  &limit=360&includeTourApi=false
```

## `POST /api/recommendations`

현재 위치와 지도 상태를 기준으로 랜덤 추천 카드와 코스 후보를 받는다.

Request:

```json
{
  "themeId": null,
  "latitude": 37.5665,
  "longitude": 126.978,
  "radiusKm": 3,
  "north": 37.59,
  "south": 37.54,
  "east": 127.02,
  "west": 126.94,
  "zoom": 10,
  "density": "summary",
  "category": "카페",
  "mode": "cafe",
  "limit": 100,
  "recentPlaceIds": ["smartSeoul-123"],
  "includeTourApi": false
}
```

Response 주요 필드:

- `generatedAt`: 서버 응답 생성 시각.
- `source`: 사용한 캐시 공급자 메타.
- `fallbackUsed`: 요청 범위 후보가 부족해 범위를 확장했거나 최근 추천 제외를 완전히 지키지 못했는지 여부.
- `randomScope`: “현재 지도 안에서 랜덤”, “서울 마포구 안에서 랜덤”, “후보 부족으로 서울 전체로 확장” 같은 UX/디버깅용 설명.
- `nearbyPick`, `mealPick`, `dateCourse`: 가벼운 추천 카드/코스 후보.
- 랜덤은 모드/카테고리 후보군을 먼저 만든 뒤 bounds, 반경, limit, 최근 추천 제외를 적용한다.
- `recentPlaceIds`는 요청 안에서만 사용한다. 서버에 사용자별 추천 이력을 저장하지 않는다.

## `POST /api/search`

검색 화면 또는 실험용 질의에서 사용한다.

Request 주요 필드:

- `query`: 필수 검색어.
- `mode`: 선택. `KEYWORD`, `VECTOR`, `HYBRID`.
- `themeId`, `latitude`, `longitude`, `radiusKm`, `topK`: 선택.

## `GET /api/events`

이벤트 목록을 받는다.

Query:

- `region`
- `themeId`
- `activeOn`
- `limit`

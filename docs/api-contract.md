# Pero API Contract

## 공통 원칙

- iOS와 웹 프런트는 외부 API를 직접 호출하지 않고 백엔드 `/api/*`만 호출한다.
- `category`는 백엔드 데이터 원본의 장소 분류다. 화면의 뽑기 모드(`장소`, `식당`, `축제`)와 같은 값으로 취급하지 않는다.
- `total`은 현재 응답에 포함된 배열 개수다. 전체 캐시 개수는 `source.count`에서 확인한다.

## `GET /api/places`

지도 핀 후보 풀을 받는다.

Query:

- `latitude`: 선택. 현재 중심 위도.
- `longitude`: 선택. 현재 중심 경도. `latitude`와 함께 보내야 한다.
- `radiusKm`: 선택. 중심 좌표 기준 반경.
- `limit`: 선택. 최대 응답 개수. 서버에서 500개로 상한 처리한다.
- `includeTourApi`: 선택. 기본값 `true`. `false`면 `tourApi`는 `null`로 내려가며 지도 핀 성능용으로 사용한다.

Response:

```json
{
  "source": {
    "providerId": "koreaTour",
    "providerName": "한국관광공사 TourAPI",
    "status": "ok",
    "generatedAt": "2026-06-09T00:00:00+09:00",
    "count": 10526
  },
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

iOS 지도 초기 풀:

```text
GET /api/places?latitude={lat}&longitude={lng}&limit=360&includeTourApi=false
```

## `POST /api/recommendations`

현재 위치 기반 추천 카드와 코스 후보를 받는다.

Request:

```json
{
  "themeId": null,
  "latitude": 37.5665,
  "longitude": 126.978,
  "radiusKm": 3
}
```

Response 주요 필드:

- `nearbyPick`: 가까운 장소 추천 카드.
- `mealPick`: 식사 후보 추천 카드.
- `dateCourse`: 여러 장소를 묶은 코스 후보.
- 각 장소의 `category`, `tags`, `themeTags`, `tourApi` 구조는 `/api/places`의 장소 구조와 맞춘다.

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

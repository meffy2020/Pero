# Pero Data ETL

## 목적

`Pero`는 앱/웹 요청 중 외부 API를 실시간 호출하지 않는다.
한국관광공사, 스마트서울맵, 카카오 같은 외부 소스는 ETL로 캐시를 만든다.
앱 검색/지도/랜덤은 캐시 데이터에서만 처리한다.

## 데이터 소스 구조

- 기본 전국 공급자: `koreaTour`
  - API: `https://apis.data.go.kr/B551011/KorService2`
  - 수집 방식
    - `full`: `areaCode2 -> sigunguCode -> areaBasedList2` 전수 순회
    - `incremental`: `areaBasedSyncList2` + `modifiedtime`
  - 대상 콘텐츠 타입: `12, 14, 15, 28, 32, 38`
  - 제외: `39 음식점`
  - 설명 필드: `detailCommon2.overview`를 `summary`에 우선 반영하고, 없을 때만 Pero 생성 문장을 fallback으로 사용
- 서울 보조 공급자: `smartSeoul`
  - 별도 캐시 파일 사용
  - 기본 API: `https://map.seoul.go.kr/openapi/v5/{OpenAPIThemeKey}/public`
  - 기본 키: `SMART_SEOUL_MAP_THEME_API_KEY`
  - 보조 입력 소스: `SMART_SEOUL_MAP_SOURCE_PATH` 또는 `SMART_SEOUL_MAP_SOURCE_URL`
  - JSON, GeoJSON, CSV fallback을 정규화 대상으로 허용
  - 테마 수집: 관광, 축제, 문화, 산책, 공원, 무장애, 반려 등 서비스 후보 테마만 콘텐츠 조회 대상으로 사용
  - 테마 제외: 학교, 통학, 병원, 약국, 중개사, 충전기, 편의시설, 출입구, 안전/안심, 행정/복지 등 비관광 테마
  - 설명 필드: `COT_CONTS_DETAIL`, 설명성 `COT_NAME_01~20/COT_VALUE_01~20`, `THM_THEME_DETAIL` 순으로 `summary`에 반영
  - 일정 필드: 공식 V5 `themes/contents/ko` 명세에는 날짜 요청 파라미터가 없다.
  - `COT_NAME_01~20`이 `일시`, `기간`, `일정`인 값을 파싱해 과거 종료 행사를 ETL에서 제외한다.
- 카페 후보
  - 실시간 카카오 장소 검색을 붙이지 않는다.
  - TourAPI 음식점 타입을 런타임에 보강하지 않는다.
  - `mode=cafe`는 현재 캐시 파일에 들어온 `카페` 성격 후보가 있을 때만 동작한다.
  - 카카오 ETL은 향후 별도 캐시 파일과 재생성 정책이 생기기 전까지 공개 런타임 계약으로 보지 않는다.
  - 후보가 부족하면 서버는 `fallbackUsed=true`와 확장된 `randomScope`를 내려준다.

## 캐시 파일

- TourAPI
  - `backend/src/main/resources/data/places.json`
  - `backend/src/main/resources/data/places.json.meta.json`
- Smart Seoul
  - `backend/src/main/resources/data/places.smartseoul.json`
  - `backend/src/main/resources/data/places.smartseoul.json.meta.json`

메타 파일 공통 필드:

- `providerId`
- `providerName`
- `generatedAt`
- `status`
- `count`

## 서버 시작 시 인덱스

요청 때마다 전체 장소를 훑지 않도록 서버 시작 시 캐시를 읽고 다음 기준으로 묶는다.

- 시도/지역
- 시군구/권역
- 카테고리
- 공급자 source
- 진행중 축제 여부

예:

- `서울 > 마포구 > 카페`
- `강원 > 강릉시 > 관광지`
- `전국 > 진행중 축제`

지도/랜덤 요청은 이 인덱스 후보군에서 시작한 뒤 bounds, 반경, mode/category, limit 조건을 적용한다.
`recentPlaceIds`는 `/api/recommendations`에서만 쓰는 요청 단위 제외 목록이며, 캐시 인덱스나 서버 저장 상태가 아니다.

## 런타임 공급자 우선순위

기본 provider order:

- `smartSeoul,koreaTour`

의미:

- 런타임은 provider 우선순위대로 캐시를 병합해 읽는다.
- 서울 데이터가 Smart Seoul 캐시에 있으면 해당 레코드를 우선 사용한다.
- Smart Seoul 캐시가 없거나 비어 있으면 TourAPI fallback을 사용한다.
- 서울 외 지역은 자연스럽게 TourAPI를 사용한다.

## 정제 규칙

- 1차 중복 제거
  - 공급자 내부 고유 ID 기준
- 2차 중복 제거
  - `name + normalized address + rounded lat/lng`
- 드롭 조건
  - 좌표 오류
  - 주소 결손
  - 관광 서비스 성격과 무관한 비관광성 POI
  - Smart Seoul 관광 후보 키워드가 없는 비관광성 테마
  - Smart Seoul 행사/축제 중 일정이 없거나 파싱되지 않는 레코드
  - Smart Seoul 일정 종료일이 캐시 생성일보다 이전인 레코드
- 테마 태그 공통 규칙
  - `서울`
  - `축제행사`
  - `자연산책`
  - `실내데이트`
  - `가족나들이`
  - `반려동물동반`
  - `무장애여행`
- TourAPI는 상세 보강 유지
  - `detailCommon2`
  - `detailIntro2`
  - `detailImage2`
  - `detailPetTour2`

## 실행

```bash
# TourAPI 전국 전량 dry-run
python3 scripts/etl/sync_places.py --provider koreaTour --mode full --dry-run

# TourAPI 전국 전량 캐시 생성
python3 scripts/etl/sync_places.py --provider koreaTour --mode full

# TourAPI 증분 동기화
python3 scripts/etl/sync_places.py --provider koreaTour --mode incremental

# Smart Seoul 공식 V5 API 기반 캐시 생성
python3 scripts/etl/sync_places.py --provider smartSeoul --mode full

# Smart Seoul 소스 파일 기반 fallback 캐시 생성
python3 scripts/etl/sync_places.py --provider smartSeoul --mode full --source-path /path/to/source.json

# Smart Seoul 소스 URL 기반 dry-run
python3 scripts/etl/sync_places.py --provider smartSeoul --mode full --source-url https://example.com/source.geojson --dry-run

# Smart Seoul 증분 동기화
python3 scripts/etl/sync_places.py --provider smartSeoul --mode incremental --source-path /path/to/source-dir
```

옵션:

- `--max-places 0`
  - 무제한 수집
- `--area-codes`
  - TourAPI 일부 지역만 점검할 때 사용
- `--modified-since YYYYMMDDHHMMSS`
  - TourAPI incremental 기준시각 강제 지정
- `smartSeoul --mode incremental`
  - 소스 레코드에 수정시각 필드가 있을 때만 변경분만 채택
  - 수정시각 필드가 없으면 full scan 후 `incremental-fallback-full-scan` 통계가 남음
- `--strict`
  - 첫 오류에서 즉시 중단

## 운영 포인트

- 프런트와 iOS는 외부 API를 직접 호출하지 않는다.
- `/api/search`, `/api/places`, `/api/recommendations`, `/api/themes`, `/api/events`는 캐시 기반으로만 동작한다.
- `source`, `generatedAt`, `fallbackUsed`, `randomScope`는 현재 어떤 캐시/범위가 응답에 쓰였는지 설명 가능해야 한다.
- 지도/랜덤 클라이언트는 `includeTourApi=false`를 명시해 상세 payload를 줄인다. 서버 wire 기본값은 기존 호환을 위해 `true`다.
- Smart Seoul 소스가 준비되지 않았더라도 서버는 TourAPI fallback으로 계속 동작해야 한다.

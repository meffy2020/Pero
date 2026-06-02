# Pero Data ETL

## 목적

`Pero`는 외부 API를 프런트에서 직접 호출하지 않고, 백엔드 ETL이 만든 정적 캐시를 기본 데이터 소스로 사용한다.
이 문서는 `TourAPI 전국 전량 + Smart Seoul 서울 전량` 구조와 정제 규칙을 운영 기준으로 고정한다.

## 데이터 소스 구조

- 기본 전국 공급자: `koreaTour`
  - API: `https://apis.data.go.kr/B551011/KorService2`
  - 수집 방식
    - `full`: `areaCode2 -> sigunguCode -> areaBasedList2` 전수 순회
    - `incremental`: `areaBasedSyncList2` + `modifiedtime`
  - 대상 콘텐츠 타입: `12, 14, 15, 28, 32, 38`
  - 제외: `39 음식점`
- 서울 보조 공급자: `smartSeoul`
  - 별도 캐시 파일 사용
  - 입력 소스: `SMART_SEOUL_MAP_SOURCE_PATH` 또는 `SMART_SEOUL_MAP_SOURCE_URL`
  - JSON, GeoJSON, CSV를 정규화 대상으로 허용

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

## 런타임 공급자 우선순위

기본 provider order:
- `smartSeoul,koreaTour`

의미:
- 런타임은 provider 우선순위대로 캐시를 병합해 읽음
- 서울 데이터가 Smart Seoul 캐시에 있으면 해당 레코드를 우선 사용
- Smart Seoul 캐시가 없거나 비어 있으면 TourAPI fallback
- 서울 외 지역은 자연스럽게 TourAPI 사용

## 정제 규칙

- 1차 중복 제거
  - 공급자 내부 고유 ID 기준
- 2차 중복 제거
  - `name + normalized address + rounded lat/lng`
- 드롭 조건
  - 음식점/브런치/카페 중심 장소
  - 좌표 오류
  - 주소 결손
  - 관광 서비스 성격과 무관한 비관광성 POI
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

# Smart Seoul 소스 파일 기반 캐시 생성
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

- 프런트는 외부 API를 직접 호출하지 않는다.
- `/api/search`, `/api/places`, `/api/recommendations`, `/api/themes`, `/api/events`는 캐시 기반으로만 동작한다.
- `source` 메타는 현재 어떤 공급자 캐시가 응답에 쓰였는지 설명 가능해야 한다.
- Smart Seoul 소스가 준비되지 않았더라도 서버는 TourAPI fallback으로 계속 동작해야 한다.

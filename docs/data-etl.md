# Pero Data ETL

## 목적

서버가 외부 API 상태에 직접 흔들리지 않도록 `places.json` 기반 정적 캐시를 기본 데이터 소스로 유지한다.
핵심 목표는 한국관광공사 KorService2 데이터를 재현 가능한 스크립트로 동기화하고,
`places.json.meta.json`으로 공급자 상태와 생성 시각을 함께 남겨 검색 결과의 근거를 설명 가능하게 만드는 것이다.

## 데이터 소스 구조

- 기본 공급자: `koreaTour`
  - API: `https://apis.data.go.kr/B551011/KorService2/locationBasedList2`
  - 수집 스크립트: `scripts/etl/sync_places.py`
  - 인증키: `.env`의 `KOREA_TOUR_API_SERVICE_KEY`
    - 하위호환으로 `KOREA_TOUR_API_KEY`도 동작
  - 전국 주요 시도 중심 좌표에서 반경 수집 + 콘텐츠 유형(12/14/28/38/39) 우선 수집
- 임시/레거시 스크립트: `scripts/etl/kakao_places_to_pero.py`
  - KorService2 도입 전 샘플 수집용으로 남겨둔 참고 구현
  - 기본 시연 캐시는 이제 KorService2 기준으로 본다
- 보조 공급자: `smartSeoul`
  - 현재는 비활성 토글 전제, 추후 별도 캐시 파일로 확장

## 캐시 파일

- 대상 경로
  - `backend/src/main/resources/data/places.json`
  - `backend/src/main/resources/data/places.json.meta.json`
- `places.json`
  - `PlaceSeed` 배열
  - 필드: `id`, `name`, `category`, `district`, `address`, `roadAddress`, `latitude`, `longitude`, `summary`, `tags`, `searchHints`
- `places.json.meta.json`
  - `providerId`, `providerName`, `generatedAt`, `status`, `count`

예시:

```json
{
  "providerId": "koreaTour",
  "providerName": "한국관광공사 API 동기화 캐시",
  "generatedAt": "2026-04-21T17:35:46+09:00",
  "status": "ok",
  "count": 100
}
```

## providerId / providerName 정합 규칙

- `providerId`
  - 백엔드 `KoreaTourPlaceDataProvider`와 동일하게 항상 `koreaTour`
- `providerName`
  - 백엔드 표시명과 동일하게 항상 `한국관광공사 API 동기화 캐시`
- 기본 `places.json`은 한국관광공사 캐시 전용으로 취급한다
- 다른 원천 데이터를 기본 캐시에 쓰려면 공급자 명칭을 섞지 말고 별도 캐시 파일과 별도 provider를 두는 편이 맞다

## PlaceSeed 필드 매핑 규칙

KorService2 `locationBasedList2` 응답을 `PlaceSeed`로 정규화할 때의 기준은 아래와 같다.

| PlaceSeed 필드 | KorService2 필드 / 규칙 |
|---|---|
| `id` | `koreaTour-{contentid}` |
| `name` | `title` |
| `category` | `contenttypeid` 기반 매핑(`관광지`, `문화시설`, `레포츠`, `숙박`, `쇼핑`, `음식점`) 우선 |
| `district` | `addr1`에서 시/도 + 시군구를 파싱, 실패 시 수집 타깃 기본값 사용 |
| `address` | `addr1` + `addr2` 병합 |
| `roadAddress` | 별도 도로명 주소 필드가 없으므로 `address`와 동일값 사용 |
| `latitude` | `mapy` |
| `longitude` | `mapx` |
| `summary` | 카테고리 + 권역 + 태그 기반 템플릿 문장 |
| `tags` | 카테고리, 행정구역, 권역 테마(데이트/산책/전시/식사 등) 조합 후 중복 제거 |
| `searchHints` | 출처, 권역 반경, 주소, 자연어 질의 연결 힌트 |

## 수집 대상 / 정렬 규칙

- 기본 호출은 `locationBasedList2`
- 타깃마다 `contentTypeId`를 나눠 호출한다
  - 기본 포함: `12`, `14`, `28`, `38`, `39`
- 정렬은 거리순(`arrange=E`)을 사용한다
- `--max-places`에 도달하면 즉시 종료한다
- 수집 대상은 기본 시퀀스에서 전국 주요 시도(서울, 경기, 강원, 충북, 충남, 전북, 전남, 경북, 경남, 부산, 대구, 인천, 광주, 대전, 울산, 세종, 제주)로 균등 분배한다.

## 유효성 규칙

### 좌표

- `mapy`, `mapx`를 각각 `latitude`, `longitude`로 파싱
- 숫자 변환 실패 시 드롭
- 대한민국 경계 대략값 바깥이면 드롭
  - 위도 `32.0 ~ 39.5`
  - 경도 `123.0 ~ 132.5`

### 주소

- `addr1` + `addr2` 병합 결과가 비어 있거나 지나치게 짧으면 드롭
- 행정/도로 키워드(`시`, `도`, `구`, `군`, `읍`, `면`, `동`, `로`, `길`)가 없으면 드롭
- 별도 도로명 주소 필드가 없으므로 `roadAddress`는 `address`와 동일하게 채운다

### 이름 / ID

- `contentid`가 없으면 드롭
- `title`이 비어 있으면 드롭

## 중복 제거 규칙

- 1차 키: `contentid`
  - 동일 `contentid`가 다시 나오면 더 정보량이 많은 레코드만 남긴다
- 2차 키: `name + address + rounded(lat/lng)` 시그니처
  - 권역/카테고리 중복 호출로 같은 장소가 다시 나오면 제거한다

## 실패 허용 로직

- 기본 모드는 부분 실패 허용
  - 네트워크, HTTP, 응답 파싱 오류가 나도 현재 페이지/카테고리만 중단하고 다음 호출로 넘어간다
- `--strict`
  - 첫 오류에서 즉시 중단한다
- 잘못된 레코드는 전체 ETL을 실패시키지 않고 드롭 통계만 남긴다
- 최종 상태값은 아래 규칙을 따른다
  - 정상 수집: `ok`
  - 일부 요청 실패가 있었지만 결과가 남음: `partial`
  - 결과는 없고 일부 요청 실패가 있었음: `empty-partial`
  - 결과 자체가 없음: `empty`

## dry-run 통계

`--dry-run`은 파일을 쓰지 않고 아래 정보를 JSON으로 출력한다.

- `providerId`, `providerName`, `status`, `count`
- `stats`
  - `requestCount`
  - `apiErrorCount`
  - `parseErrorCount`
  - `rawItemCount`
  - `acceptedCount`
  - `duplicateContentIdCount`
  - `duplicateSignatureCount`
  - `targetCount`
  - `droppedByReason`
- `sample`
  - 정규화된 `PlaceSeed` 샘플 최대 3건

이 출력으로 수집 품질, 드롭 사유, 권역별 중복 상황을 먼저 확인한 다음 실제 파일 쓰기를 수행한다.

## 로컬 실행

`.env`

```env
KOREA_TOUR_API_SERVICE_KEY=...
KOREA_TOUR_ENDPOINT=https://apis.data.go.kr/B551011/KorService2
```

- 레거시 호환
  - 기존 `.env`에 `KOREA_TOUR_API_KEY`만 있어도 스크립트는 읽을 수 있다
  - 운영은 `KOREA_TOUR_API_SERVICE_KEY`를 기본값으로 간주한다

실행 예시:

```bash
# 통계만 먼저 확인
python3 scripts/etl/sync_places.py --dry-run --max-places 100

# 실제 캐시 생성
python3 scripts/etl/sync_places.py --max-places 100

# sidecar 생성을 원치 않을 때
python3 scripts/etl/sync_places.py --max-places 100 --no-meta

# API 오류가 하나라도 나면 즉시 중단
python3 scripts/etl/sync_places.py --max-places 100 --strict
```

옵션 메모:

- `--max-places`
  - 전역 유니크 장소 상한
  - 상한 도달 시 남은 권역/카테고리 호출 없이 종료
- `--num-of-rows`
  - 페이지당 요청 건수
- `--pause`
  - API 호출 사이 sleep 초
- `--dry-run`
  - 파일 미생성, 통계와 샘플만 출력
- `--strict`
  - 부분 실패 허용 없이 즉시 종료

운영 체크:

1. 인증키가 유효한지 확인
2. `places.json`이 재생성됐는지 확인
3. `places.json.meta.json`의 `generatedAt`, `count`, `status`를 확인
4. 백엔드 응답의 `source` 메타가 새 값으로 반영되는지 확인

## 운영 포인트

- 캐시 파일이 없더라도 서버는 중단되지 않아야 한다.
- `/api/search`, `/api/places`, `/api/recommendations`는 `sourceStatus` 또는 폴백 상태를 응답에 남겨야 한다.
- 검색 결과 설명 문구는 `providerId`, `status`, `generatedAt` 기반으로 해석 가능해야 한다.
- `meta` 파일은 단순 보조 파일이 아니라 "현재 데이터가 언제, 어떤 공급자 기준으로 생성됐는지"를 보여주는 운영 로그로 취급한다.

## 테스트 시나리오

1. `/api/search`
   - 캐시 있음/캐시 없음/반경 결과 0건 각각에서 200 응답 유지 확인
   - `source.providerId`, `source.sourceStatus`, `source.generatedAt` 정합성 확인
2. `/api/places`
   - 캐시 없음: 빈 목록과 상태 메타 확인
   - 캐시 있음: `total == places.size`, `source.count >= total`
3. `/api/recommendations`
   - 데이터 없음: 폴백 카드, `fallbackUsed=true` 형식 확인
   - 데이터 있음: 추천 카드/코스가 정상 구성되는지 확인

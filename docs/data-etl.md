# Pero Data ETL

## 목적

샘플 8건만으로는 검색 품질과 지도 시연을 설명하기 어렵기 때문에, 카카오 Local API에서 장소 후보를 가져와 Pero 검색 스키마로 변환한다.

## 데이터 출처

- Kakao Local API `키워드로 장소 검색`
- 사용 키: `.env`의 `KAKAO_REST_API_KEY`
- 수집 대상: 홍대입구, 연남, 성수, 잠실, 서촌 주변 장소
- 주요 키워드: 카페, 브런치, 북카페, 스터디카페, 애견카페, 베이커리, 디저트 등

## 생성 파일

```text
backend/src/main/resources/data/places.json
```

현재 백엔드는 이 JSON을 서버 시작 시 읽어서 검색 인덱스를 만든다.

## 실행 방법

루트 `.env`에 아래 값이 있어야 한다.

```env
KAKAO_REST_API_KEY=...
```

dry-run:

```bash
python3 scripts/etl/kakao_places_to_pero.py --dry-run --max-places 5
```

100건 재생성:

```bash
python3 scripts/etl/kakao_places_to_pero.py --max-places 100
```

## 변환 방식

카카오 API에서 가져오는 주요 필드:

```text
place_name
category_name
address_name
road_address_name
x
y
id
```

Pero 스키마로 변환:

```text
id           kakao-{카카오 장소 ID}
name         place_name
category     category_name의 마지막 분류
district     수집 기준 지역명
address      address_name
roadAddress  road_address_name
latitude     y
longitude    x
summary      카테고리/지역/tag 기반 자동 설명
tags         카테고리/키워드 기반 자동 태그
searchHints  검색 근거 후보 문장
```

## 태그 생성 규칙

자동 태그는 카테고리명과 검색 키워드를 기준으로 만든다.

```text
북카페
  조용한, 독서, 카공, 혼자, 차분한

스터디
  공부, 집중, 노트북, 작업, 조용한

애견 / 반려
  반려동물, 애견, 펫, 동반, 산책

키즈 / 패밀리
  가족, 아이, 유아, 주말, 넓은좌석

브런치
  브런치, 데이트, 주말, 커피, 식사

베이커리 / 디저트
  베이커리, 디저트, 커피, 데이트, 분위기

카페
  카페, 커피, 작업, 분위기, 휴식
```

## 교수님께 설명할 포인트

이 데이터는 리뷰를 무단 크롤링한 것이 아니라 공식 Kakao Local API에서 장소명, 카테고리, 주소, 좌표를 가져온 것이다.

분위기나 목적 태그는 카카오가 직접 제공하는 값이 아니라, 카테고리와 검색 키워드 기반 규칙으로 자동 보강했다.

따라서 현재 데이터는 “최종 품질 데이터셋”이 아니라, 검색 API와 지도 시연을 위한 재생성 가능한 프로토타입 데이터셋이다.

## 한계

- 자동 태그는 실제 매장 분위기를 완벽히 보장하지 않는다.
- 카카오 카테고리가 넓게 잡힌 장소는 태그 품질이 낮을 수 있다.
- 중복/폐업/운영시간 검증은 아직 하지 않았다.
- 추후 대표 장소 20~30개는 수동 검수하는 것이 좋다.

## 다음 개선

1. 장소 50~100건 중 핵심 데모 후보 20건 수동 검수
2. `openingHours`, `phone`, `placeUrl` 같은 필드 추가 검토
3. 대표 질의셋과 기대 결과 정의
4. 태그 생성 규칙을 별도 JSON/YAML로 분리
5. 데이터 출처와 생성 일자를 `places.json` 외부 메타 파일로 기록

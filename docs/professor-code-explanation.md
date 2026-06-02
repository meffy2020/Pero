# Pero 교수님 설명용 코드 핵심 개념 정리

## 1. 한 문장 설명

Pero는 사용자가 자연어로 원하는 장소 조건을 입력하면, 위치와 장소 메타데이터를 함께 반영해 후보를 찾고, 왜 그 장소가 선택됐는지 command center 형태로 설명하는 검색 프로토타입입니다.

## 2. 지금 제품이 무엇인지

중요한 점은 이 프로젝트가 `여행 계획 서비스`가 아니라는 것입니다.

핵심 기능은 3가지입니다.

- `검색`: 사용자가 문장으로 장소를 찾음
- `탐색`: 지도와 카드에서 후보를 비교함
- `해석`: inspector rail에서 추천 근거와 메타데이터를 확인함

즉, 단순한 지도 검색이 아니라 `자연어 장소 검색 + 위치 기반 후보 제한 + 추천 이유 설명`을 묶은 서비스입니다.

## 3. 전체 구조

```text
사용자
  -> Next.js 프론트엔드
  -> /api/search 요청
  -> Spring Boot 백엔드
  -> places.json / KorService2 캐시 기반 장소 데이터 로딩
  -> 키워드 점수 + 벡터 유사도 + 특징 점수 + 위치 점수 계산
  -> 검색 결과와 근거 반환
  -> 프런트에서 command center 셸로 재구성
  -> 지도 / 결과 보드 / inspector rail / recommendation board로 시각화
```

## 4. 프런트엔드 설명 포인트

프런트는 기존 단순 검색 화면에서 `command center` 셸로 바뀌었습니다.

구성은 아래처럼 설명하면 됩니다.

```text
좌측: view navigation
상단: 검색 실행 command header
중앙: overview / search ops / recommendations / compare / data intel
우측: 선택 장소 inspector rail
하단: search event strip
```

이 구조는 `andrewjiang/palantir-for-family-trips` 레포의 명령실형 대시보드 감각을 참고했지만, 여행 계획 기능을 그대로 가져온 것은 아닙니다.

재해석한 항목:
- mission -> 사용자 질의
- inspector rail -> 선택 장소 근거 패널
- activity board -> 검색 결과 보드 / 추천 보드
- launch overlay -> 검색 실행 오버레이
- timeline -> 검색 이벤트 스트립

## 5. 백엔드 계층 구조

백엔드는 그대로 Controller-Service-Repository 구조입니다.

```text
SearchController
  HTTP API 진입점

SearchService
  검색/추천 비즈니스 로직

PlaceRepository
  places.json 및 KorService2 캐시 로딩 / 검색용 인덱스 생성

DTO / Model records
  요청/응답 계약과 내부 인덱스 모델
```

교수님께는 `프런트는 표현 방식을 바꿨고, 백엔드는 같은 검색 엔진을 유지했다`고 설명하면 됩니다.

## 6. 공개 API는 유지함

프런트 리디자인은 컸지만, API 계약은 1차에서 그대로 유지했습니다.

```text
GET  /api/health
GET  /api/places
POST /api/search
POST /api/recommendations
```

즉, 이번 변경의 핵심은 `데이터 계약 변경`이 아니라 `검색 경험과 설명 방식 변경`입니다.

## 7. 교수님께 강조할 차별점

이 프로젝트의 차별점은 아래입니다.

- 사용자가 자연어로 장소를 찾는다.
- 위치 정보를 함께 써서 현실적인 후보로 좁힌다.
- 결과를 그냥 리스트로만 주지 않고, 왜 추천됐는지 근거와 메타데이터를 같이 보여준다.
- 검색, 추천, 비교, 데이터 인텔을 하나의 명령실 UI에서 다룬다.

한 줄로 말하면:

`Pero는 자연어 질의와 위치 정보를 활용해 장소를 찾고, 추천 이유를 데이터 기반으로 해석해주는 검색 command center입니다.`

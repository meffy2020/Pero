# Pero 교수님 설명용 코드 핵심 개념 정리

이 문서는 교수님께 소스 코드를 설명할 때 바로 말할 수 있도록 만든 면담용 정리입니다.

## 1. 한 문장 설명

Pero는 사용자가 자연어로 원하는 장소 조건을 입력하면, 장소 메타데이터와 현재 위치를 함께 반영해서 장소를 검색하고, 왜 그 장소가 추천됐는지 근거 문장과 점수로 설명하는 검색 프로토타입입니다.

## 2. 전체 구조

```text
사용자
  -> Next.js 프론트엔드
  -> /api/search 요청
  -> Spring Boot 백엔드
  -> places.json 샘플 장소 데이터 로딩
  -> 키워드 점수 + 벡터 유사도 + 장소 특성 점수 + 위치 점수 계산
  -> 검색 결과와 근거 반환
  -> 프론트에서 리스트, OpenStreetMap 지도, Evidence Panel로 시각화
```

핵심은 일반 키워드 검색만 하는 것이 아니라, 자연어 질의의 의도와 장소 설명/태그/위치 정보를 같이 섞어 순위를 정한다는 점입니다.

## 3. 폴더별 역할

```text
backend/
  Spring Boot 검색 API 서버

frontend/
  Next.js 기반 검색 UI와 지도 화면

backend/src/main/resources/data/places.json
  현재 샘플 장소 데이터

docs/
  개발 문서, 로드맵, 배포 문서, 발표/설명 자료
```

## 4. 백엔드 계층 구조

백엔드는 전형적인 Controller-Service-Repository 구조입니다.

```text
SearchController
  HTTP API 진입점

SearchService
  검색/추천 비즈니스 로직

PlaceRepository
  places.json 로딩과 검색용 인덱스 생성

TextNormalizer
  텍스트 정규화, 토큰화, 의미 확장

EmbeddingService
  간단한 해시 기반 임베딩 벡터 생성

DTO / Model records
  요청/응답 계약과 내부 인덱스 모델
```

교수님께 설명할 때는 “Controller는 요청을 받고, Service는 계산하고, Repository는 데이터를 준비합니다”라고 말하면 됩니다.

## 5. 백엔드 파일별 설명

### `BackendApplication.java`

Spring Boot 애플리케이션 시작점입니다. `SpringApplication.run()`으로 서버를 실행합니다.

### `WebConfig.java`

프론트엔드가 백엔드 API를 호출할 수 있도록 CORS를 설정합니다. 개발 환경에서는 `localhost:3000` 같은 프론트 주소를 허용합니다.

### `SearchController.java`

외부로 공개되는 API를 정의합니다.

```text
GET  /api/health
  서버 상태 확인

GET  /api/places
  로딩된 장소 목록 확인

POST /api/search
  자연어 검색

POST /api/recommendations
  위치 기반 추천/코스 생성
```

Controller에는 계산 로직을 넣지 않고, `SearchService`에 위임합니다. 이렇게 하면 API 계층과 검색 로직을 분리할 수 있습니다.

### `SearchRequest.java`

검색 요청 형식입니다.

```text
query      자연어 검색어
mode       KEYWORD / VECTOR / HYBRID
latitude   위도
longitude  경도
radiusKm   검색 반경
topK       반환 개수
```

`@NotBlank`, `@DecimalMin`, `@DecimalMax`, `@Min`, `@Max` 같은 Jakarta Validation을 사용해서 잘못된 요청을 초기에 막습니다.

### `SearchResponse.java`

검색 응답 형식입니다.

```text
query        원본 질의
mode         적용된 검색 모드
total        반환 결과 수
topK         요청 상위 K개
generatedAt  생성 시간
results      장소 결과 목록
```

### `PlaceResultResponse.java`

장소 하나의 검색 결과입니다.

```text
장소 기본 정보
좌표
거리
근거 문장
keywordScore
vectorScore
featureScore
geoScore
finalScore
```

이 구조 덕분에 프론트에서 단순히 장소명만 보여주는 것이 아니라, “왜 이 결과가 나왔는지”를 함께 보여줄 수 있습니다.

### `PlaceSeed.java`

`places.json`의 원본 데이터 구조입니다. 사람이 작성한 샘플 장소 데이터입니다.

### `IndexedPlace.java`

검색을 빠르게 하기 위해 원본 장소를 미리 가공한 내부 모델입니다.

```text
termFrequencies
  BM25 키워드 검색에 필요한 단어 빈도

featureTokens
  태그, 카테고리, 요약, 힌트에서 뽑은 특징 토큰

embedding
  장소 전체 텍스트를 벡터화한 값

evidenceCandidates
  근거 문장 후보와 각 후보의 벡터
```

즉, `PlaceSeed`는 원본 데이터이고 `IndexedPlace`는 검색용으로 전처리된 데이터입니다.

### `PlaceRepository.java`

서버 시작 시 `places.json`을 읽어서 `IndexedPlace` 목록을 만듭니다.

처리 흐름:

```text
places.json 읽기
  -> 장소명, 카테고리, 주소, 요약, 태그, 힌트를 하나의 searchableText로 합침
  -> TextNormalizer로 토큰화
  -> 단어 빈도(term frequency) 계산
  -> featureTokens 생성
  -> evidence 후보 문장 생성
  -> EmbeddingService로 장소 벡터 생성
  -> IndexedPlace로 저장
```

현재는 DB 대신 JSON 파일을 사용합니다. 이유는 졸업작품 초기 단계에서 데이터 구조와 검색 로직을 빠르게 검증하기 위해서입니다. 추후에는 DB 또는 OpenSearch로 바꿀 수 있습니다.

### `TextNormalizer.java`

검색어와 장소 데이터를 같은 기준으로 비교하기 위해 텍스트를 정규화합니다.

기능:

```text
normalize()
  소문자화, 특수문자 제거, 공백 정리

compact()
  공백까지 제거한 문자열 생성

tokenize()
  한글/영문/숫자 토큰 추출

tokenizeForSearch()
  기본 토큰 + 의미 확장 토큰 생성
```

의미 확장 예시:

```text
조용 -> 한적, 차분, 집중, 북카페
공부 -> 집중, 노트북, 콘센트, 작업
반려동물 -> 애견, 펫, 강아지, 동반
데이트 -> 분위기, 야간, 와인
```

교수님께는 “사용자가 정확히 같은 단어를 입력하지 않아도 비슷한 의도를 찾도록 간단한 동의어 확장을 넣었습니다”라고 설명하면 됩니다.

### `EmbeddingService.java`

외부 AI API 없이 로컬에서 간단한 벡터를 만듭니다.

구현 방식:

```text
토큰을 해시해서 96차원 배열의 위치에 누적
한글/문자열 bigram, trigram도 일부 반영
벡터를 정규화
cosine similarity로 질의와 장소의 유사도 계산
```

중요한 설명:

```text
이 임베딩은 OpenAI나 BERT 같은 실제 의미 임베딩은 아닙니다.
프로토타입에서 벡터 검색 개념을 구현하기 위한 경량 해시 임베딩입니다.
나중에 실제 임베딩 모델이나 OpenSearch k-NN으로 교체할 수 있게 SearchService와 분리했습니다.
```

### `SearchService.java`

검색의 핵심 로직입니다.

검색 흐름:

```text
1. 위도/경도 유효성 검증
2. 반경 안 장소만 후보로 필터링
3. 검색어 토큰화
4. 검색어 임베딩 생성
5. 후보별 점수 계산
6. KEYWORD/VECTOR/HYBRID 모드별 최종 점수 계산
7. finalScore 기준 정렬
8. 상위 topK 반환
```

## 6. 검색 알고리즘 핵심

### 6.1 키워드 점수

BM25 계열 점수를 사용합니다.

BM25는 단순히 단어가 있는지만 보는 것이 아니라, 다음을 반영합니다.

```text
단어가 해당 문서에 얼마나 자주 등장하는지
그 단어가 전체 문서에서 얼마나 희소한지
문서 길이가 너무 길어서 유리해지는 문제를 보정
```

교수님 답변:

```text
키워드 검색은 BM25 방식을 참고했습니다. 단어 빈도와 역문서빈도를 사용해서 흔한 단어보다 검색 의도를 잘 설명하는 단어에 더 높은 점수를 줍니다.
```

### 6.2 벡터 점수

질의와 장소 설명을 각각 96차원 벡터로 바꾸고 cosine similarity를 구합니다.

```text
cosine similarity가 1에 가까울수록 방향이 비슷함
방향이 비슷하다는 것은 토큰/부분 문자열 특징이 비슷하다는 뜻
```

교수님 답변:

```text
현재는 외부 임베딩 모델을 쓰지 않고 해시 기반 벡터를 사용했습니다. 실제 의미 이해 성능은 제한적이지만, 벡터 검색 구조와 API 계약을 먼저 검증하기 위한 프로토타입입니다.
```

### 6.3 특징 점수

장소의 태그, 카테고리, 요약, 검색 힌트에서 뽑은 `featureTokens`와 검색어 토큰이 얼마나 겹치는지 봅니다.

```text
예: 검색어 "공부하기 좋은 카페"
확장 토큰: 공부, 집중, 노트북, 콘센트, 작업
장소 태그: 조용한, 공부, 노트북, 콘센트
-> featureScore 상승
```

### 6.4 위치 점수

Haversine 공식을 사용해 두 위도/경도 사이 거리를 계산합니다.

```text
geoScore = 1 - (distanceKm / radiusKm)
```

가까울수록 1에 가깝고, 반경 끝에 가까울수록 0에 가까워집니다.

교수님 답변:

```text
장소 검색은 관련성만 높다고 좋은 결과가 아니기 때문에, 현재 위치 기준 접근성도 점수에 반영했습니다.
```

### 6.5 HYBRID 검색

HYBRID는 키워드 순위와 벡터 순위를 RRF 방식으로 합칩니다.

RRF는 Reciprocal Rank Fusion입니다.

```text
각 검색 방식에서 상위에 있는 결과에 더 높은 점수 부여
keywordRank와 vectorRank를 직접 점수 평균하지 않고 순위 기반으로 합침
```

장점:

```text
키워드 점수와 벡터 점수의 스케일이 달라도 안정적으로 합칠 수 있음
한쪽 검색 방식에만 과도하게 의존하지 않음
```

## 7. 검색 모드별 설명

### KEYWORD

정확한 단어 매칭 중심입니다.

```text
위치 있음:
0.7 keyword + 0.2 geo + 0.1 feature

위치 없음:
0.85 keyword + 0.15 feature
```

언제 유리한가:

```text
"북카페", "반려동물", "브런치"처럼 명확한 단어가 있을 때
```

### VECTOR

질의와 장소 설명의 문맥 유사도 중심입니다.

```text
위치 있음:
0.65 vector + 0.2 geo + 0.15 feature

위치 없음:
0.8 vector + 0.2 feature
```

언제 유리한가:

```text
"분위기 좋은 곳", "혼자 오래 있기 좋은 곳"처럼 문장형 의도가 있을 때
```

### HYBRID

키워드와 벡터 순위를 결합합니다.

```text
위치 있음:
0.6 rrf + 0.25 geo + 0.15 feature

위치 없음:
0.8 rrf + 0.2 feature
```

기본값으로 HYBRID를 사용합니다. 이유는 자연어 검색에서 정확한 단어와 문맥을 모두 잡는 것이 안정적이기 때문입니다.

## 8. 근거 문장 생성 방식

각 장소는 여러 근거 후보를 가집니다.

```text
summary
category + district
tag 기반 문장
searchHints
```

검색 시에는 질의 임베딩과 각 근거 후보 임베딩의 cosine similarity를 비교해서 가장 유사한 근거 문장을 선택합니다.

교수님 답변:

```text
근거 문장은 LLM으로 생성한 것이 아니라, 장소 메타데이터에서 만든 후보 문장 중 질의와 가장 가까운 문장을 선택하는 방식입니다. 그래서 프로토타입 단계에서 재현 가능하고 설명 가능합니다.
```

## 9. 추천 API 설명

`/api/recommendations`는 검색어 없이 위치와 반경만으로 추천합니다.

구성:

```text
nearbyPick
  반경 안 가까운 후보 중 랜덤 추천

mealPick
  브런치/레스토랑/베이커리 성격 장소 추천

dateCourse
  식사 -> 카페 -> 마무리 3단계 코스
```

랜덤이지만 완전 무작위가 아니라 가까운 후보 상위 band 안에서 뽑습니다. 시연 시 매번 조금 다른 후보를 보여줄 수 있습니다.

## 10. 프론트엔드 구조

프론트는 Next.js App Router 기반입니다.

```text
layout.tsx
  전체 HTML, 메타데이터, 폰트 설정

page.tsx
  검색 화면의 상태와 UI 전체 구성

search-map.tsx
  Leaflet + OpenStreetMap 지도 컴포넌트

search-types.ts
  백엔드 API 응답과 동일한 TypeScript 타입

globals.css
  전체 디자인 시스템과 화면 레이아웃 스타일

next.config.ts
  /api 요청을 Spring Boot 백엔드로 프록시
```

## 11. `page.tsx` 설명

`page.tsx`는 사용자 화면의 중심입니다.

주요 상태:

```text
query
  검색어

locationId / latitude / longitude / locationLabel
  검색 기준 위치

radiusKm
  검색 반경

searchMode
  KEYWORD / VECTOR / HYBRID

response
  검색 응답

selectedPlaceId
  현재 선택된 장소

loading / locating / error
  UI 상태
```

중요한 점:

```text
현재 프론트는 시연 화면 완성도를 위해 demoResults를 기본값으로 가지고 있습니다.
백엔드가 꺼져 있어도 화면이 비지 않고, 리스트/지도/Evidence Panel이 유지됩니다.
백엔드가 켜져 있으면 /api/search 결과로 대체됩니다.
```

교수님께 이렇게 설명하면 됩니다.

```text
실제 검색 API와 연결되어 있지만, 시연 안정성을 위해 프론트에는 fallback demo data를 넣었습니다. 백엔드가 정상 동작하면 실제 검색 결과를 사용하고, 실패하면 데모 화면이 유지됩니다.
```

## 12. `search-map.tsx` 설명

지도는 Leaflet 라이브러리와 OpenStreetMap 타일을 사용합니다.

핵심 기능:

```text
처음 렌더링 시 Leaflet map 생성
OpenStreetMap tileLayer 연결
검색 결과 좌표에 커스텀 마커 생성
마커 클릭 시 selectedPlaceId 변경
리스트 카드 클릭 시 지도 flyTo
선택 장소를 중심으로 지도 이동
scale control 표시
ResizeObserver로 지도 크기 변화 대응
```

왜 Leaflet/OpenStreetMap인가:

```text
무료 오픈소스 기반으로 빠르게 지도 시각화를 붙일 수 있고, API 키 의존이 없습니다.
졸업작품 시연에서는 실제 지도 위에서 결과가 움직이는 것이 중요해서 Leaflet을 선택했습니다.
```

## 13. `search-types.ts` 설명

프론트에서 백엔드 응답 구조를 TypeScript 타입으로 정의합니다.

장점:

```text
백엔드 응답 필드 이름이 바뀌면 프론트에서 타입 오류로 빨리 알 수 있음
ResultCard, EvidencePanel, SearchMap이 같은 데이터 구조를 공유함
```

## 14. `globals.css` 설명

현재 UI는 Stitch 디자인 시안을 기준으로 맞춘 시연형 화면입니다.

디자인 방향:

```text
상단 얇은 내비게이션
좌측 고정 사이드바
좌측 검색 결과 레일
우측 풀스크린 지도
지도 위 Evidence Panel
흑백/네이비 중심의 정밀 검색 UI
```

교수님께는 “기능 구현보다 시연 화면 완성도를 위해 Stitch 시안을 기준으로 앱 쉘을 정리했습니다”라고 말하면 됩니다.

## 15. Next.js API rewrite 설명

`frontend/next.config.ts`에서 다음 rewrite를 설정합니다.

```text
/api/:path*
  -> http://localhost:8080/api/:path*
```

프론트 코드는 `/api/search`만 호출하지만, 실제 요청은 백엔드 `localhost:8080/api/search`로 전달됩니다.

장점:

```text
프론트 코드에서 백엔드 주소를 직접 하드코딩하지 않아도 됨
개발 중 CORS 문제를 줄일 수 있음
배포 시 프록시 구조로 바꾸기 쉬움
```

## 16. 실행 흐름 설명

시연 기준 흐름:

```text
1. frontend 실행
   cd frontend
   npm run dev

2. backend 실행
   cd backend
   ./gradlew bootRun

3. 브라우저 접속
   http://localhost:3000

4. 검색어 입력
   예: 조용하게 오래 머물 수 있는 카페

5. 프론트가 /api/search 호출

6. 백엔드가 점수 계산 후 결과 반환

7. 프론트가 리스트, 지도 마커, Evidence Panel 갱신
```

## 17. 교수님 예상 질문과 답변

### Q1. 이 프로젝트의 핵심 차별점은 무엇인가요?

자연어 장소 검색에서 단순히 장소 리스트만 보여주는 것이 아니라, 장소 메타데이터와 위치 정보를 함께 반영하고 추천 근거까지 보여준다는 점입니다.

### Q2. 왜 리뷰 데이터가 아니라 메타데이터 기반인가요?

초기에는 리뷰 기반도 고려했지만, 졸업작품 범위에서는 신뢰 가능한 리뷰 수집과 품질 관리가 부담이 컸습니다. 그래서 장소 설명, 태그, 카테고리, 검색 힌트처럼 구조화 가능한 메타데이터를 먼저 사용했습니다.

### Q3. 실제 AI 임베딩을 쓰나요?

현재는 외부 AI 임베딩 API가 아니라 해시 기반 경량 임베딩입니다. 목적은 벡터 검색 구조를 구현하고 HYBRID 랭킹 흐름을 검증하는 것입니다. 추후 실제 임베딩 모델이나 OpenSearch k-NN으로 대체할 수 있습니다.

### Q4. BM25는 왜 사용했나요?

일반적인 키워드 검색에서 검증된 방식이고, 단어 빈도와 희소성을 함께 반영할 수 있기 때문입니다. 단순 문자열 포함 검색보다 검색어의 중요도를 더 잘 반영합니다.

### Q5. HYBRID 검색은 왜 필요한가요?

키워드 검색은 정확한 단어에 강하고, 벡터 검색은 문장형 의도에 강합니다. HYBRID는 둘을 결합해서 어느 한쪽에만 의존하지 않도록 합니다.

### Q6. 위치 정보는 어떻게 반영하나요?

Haversine 공식으로 사용자 위치와 장소 좌표 사이 거리를 계산하고, 반경 안에 있는 장소만 후보로 사용합니다. 가까울수록 geoScore가 높아집니다.

### Q7. 검색 근거는 어떻게 만드나요?

장소 요약, 카테고리, 태그, 검색 힌트로 근거 후보 문장을 만들고, 검색어와 가장 유사한 후보 문장을 cosine similarity로 선택합니다.

### Q8. 왜 DB를 안 쓰고 JSON을 쓰나요?

현재는 검색 알고리즘과 화면 흐름 검증이 우선이라 JSON으로 빠르게 프로토타입을 만들었습니다. 데이터가 늘어나면 DB 또는 OpenSearch로 이전할 계획입니다.

### Q9. 데이터가 8건이면 검색 품질 평가가 어렵지 않나요?

맞습니다. 현재는 구조 검증 단계이고, 다음 단계는 50~100건 수준으로 데이터셋을 확장하고 대표 질의셋을 만들어 평가하는 것입니다.

### Q10. OpenSearch는 왜 아직 안 붙였나요?

초기 단계에서는 Spring Boot 내부 로직으로 랭킹 방식을 명확히 설명할 수 있게 구현했습니다. OpenSearch는 데이터가 커지고 실서비스형 검색 성능이 필요할 때 붙일 계획입니다.

### Q11. 프론트에 demoResults가 있는 이유는 무엇인가요?

시연 안정성을 위해서입니다. 백엔드가 꺼져 있거나 네트워크 문제가 생겨도 화면이 비지 않게 하고, 디자인 시안과 지도/Evidence Panel을 항상 보여주기 위해 fallback 데이터를 넣었습니다.

### Q12. 프론트와 백엔드는 어떻게 연결되나요?

프론트는 `/api/search`로 요청하고, Next.js rewrite가 이를 `http://localhost:8080/api/search`로 넘깁니다.

### Q13. 지도는 어떤 기술을 사용했나요?

Leaflet과 OpenStreetMap을 사용했습니다. API 키 없이 사용할 수 있고, 오픈소스 기반이라 졸업작품 시연에 적합합니다.

### Q14. 지도와 리스트는 어떻게 동기화되나요?

프론트에서 `selectedPlaceId` 상태를 공유합니다. 리스트 카드를 누르면 `selectedPlaceId`가 바뀌고, 지도 컴포넌트가 해당 장소 좌표로 이동합니다. 마커를 눌러도 같은 상태가 바뀝니다.

### Q15. Evidence Panel은 어떤 역할인가요?

선택한 장소의 추천 근거, 좌표, 거리, 최종 점수, 점수 구성 요소를 보여줍니다. 사용자가 결과를 납득할 수 있게 하는 핵심 UI입니다.

### Q16. 점수는 완전히 정확한가요?

현재 점수는 프로토타입용 상대 점수입니다. 절대적인 정답률을 의미하지 않고, 후보 간 순위를 정하기 위한 기준입니다.

### Q17. 검증은 어떻게 할 계획인가요?

대표 질의셋을 만들고, 각 질의에 대해 기대되는 상위 결과를 정의한 뒤, 변경 후 순위가 크게 흔들리는지 확인하는 방식으로 평가할 계획입니다.

### Q18. 확장한다면 무엇을 먼저 하나요?

데이터셋 확장이 1순위입니다. 그다음 대표 질의셋, 검색 로그 저장, OpenSearch 또는 실제 임베딩 모델 도입 순서가 적절합니다.

### Q19. 현재 한계는 무엇인가요?

데이터 수가 적고, 해시 기반 임베딩이라 실제 의미 이해가 제한적입니다. 또한 사용자 로그나 개인화는 아직 없습니다.

### Q20. 그래도 왜 이 구조가 의미 있나요?

검색 API 계약, 랭킹 파이프라인, 위치 기반 필터링, 근거 설명 UI가 모두 분리되어 있어 다음 단계로 데이터와 검색 엔진을 교체해도 전체 구조를 유지할 수 있기 때문입니다.

## 18. 코드 설명 순서 추천

교수님께 코드를 보여줄 때는 다음 순서가 좋습니다.

```text
1. README.md
   프로젝트 목적과 실행 방법

2. backend/src/main/resources/data/places.json
   어떤 데이터를 검색하는지

3. PlaceRepository.java
   데이터를 검색 가능한 형태로 전처리하는 방식

4. TextNormalizer.java
   자연어 검색어를 어떻게 토큰화/확장하는지

5. EmbeddingService.java
   벡터 검색 개념을 어떻게 구현했는지

6. SearchService.java
   점수 계산과 HYBRID 랭킹

7. SearchController.java
   API 엔드포인트

8. frontend/src/app/search-types.ts
   백엔드 응답 계약을 프론트 타입으로 연결

9. frontend/src/app/page.tsx
   검색 상태와 UI 렌더링

10. frontend/src/app/components/search-map.tsx
    OpenStreetMap 지도와 선택 상태 동기화
```

## 19. 발표 중 피해야 할 표현

피해야 할 말:

```text
AI가 알아서 추천합니다.
완성된 검색 엔진입니다.
실제 의미 임베딩을 사용했습니다.
데이터 품질 검증이 끝났습니다.
```

대신 이렇게 말하는 것이 안전합니다.

```text
자연어 질의를 토큰화하고 의미 확장한 뒤, 키워드 점수와 경량 벡터 유사도, 위치 점수를 조합했습니다.
현재는 검색 구조 검증용 프로토타입입니다.
추후 실제 임베딩 모델과 OpenSearch로 교체 가능한 구조로 분리했습니다.
검색 결과에는 근거 문장을 함께 제공해 설명 가능성을 확보했습니다.
```

## 20. 가장 중요한 방어 논리

이 프로젝트는 “검색 품질을 최종 완성했다”가 아니라 “자연어 장소 검색을 위한 설명 가능한 검색 파이프라인을 구현했다”가 핵심입니다.

방어 포인트:

```text
Controller-Service-Repository로 구조 분리
DTO로 API 계약 명확화
텍스트 정규화와 의미 확장 구현
BM25 기반 키워드 검색 구현
해시 임베딩 기반 벡터 검색 구현
RRF 기반 HYBRID 검색 구현
Haversine 기반 위치 점수 구현
근거 문장 선택 로직 구현
Next.js와 Spring Boot API 연결
OpenStreetMap 기반 지도 시각화
결과 리스트와 지도 선택 상태 동기화
```

이 정도를 설명하면 교수님이 어느 파일을 물어봐도 “그 파일이 전체 검색 흐름에서 어떤 책임을 맡는지” 답할 수 있습니다.

# Pero 개발 통합 문서

## 서비스 한 줄

- `Pero`는 장소 메타데이터와 위치 정보를 같이 보는 자연어 장소 검색 서비스임.

## 주제 변경했음

- 원래는 리뷰 기반 검색으로 잡았음.
- 리뷰 데이터 확보가 어려워서 주제 조정했음.
- 지금은 장소명, 카테고리, 설명, 태그, 주소, 좌표를 활용하는 방향으로 감.
- 발표와 시연 기준도 메타데이터 + 위치 기반 검색으로 설명하면 됨.

## 지금까지 했음

- Spring Boot 검색 API 구현했음.
- Next.js 검색 화면 구현했음.
- 실제 지도 연동했음.
- 자연어 질의 검색 붙였음.
- HYBRID 검색 붙였음.
- 거리 기반 반경 필터 붙였음.
- 검색 근거 문장 반환 붙였음.
- 주소 정보 응답에 포함했음.
- 프론트 lint 통과시켰음.
- 프론트 build 통과시켰음.
- 백엔드 test 통과시켰음.

## 아직 안 했음

- 데이터 8건밖에 없음.
- OpenSearch 아직 안 붙였음.
- 실제 임베딩 모델 아직 안 붙였음.
- 검색 로그 저장 아직 안 붙였음.
- 평가용 질의셋 아직 안 만들었음.
- Docker Compose 아직 안 만들었음.

## 폴더 정리

- `backend/`: 검색 API 있음.
- `frontend/`: 검색 화면 있음.
- `docs/`: 문서 모아둠.
- `docs/architecture/`: 아키텍처 참고 문서 있음.
- `docs/project-roadmap.md`: 짧은 로드맵 메모 있음.

## 실행 방법

### 백엔드 실행했음

```bash
cd backend
./gradlew bootRun
```

- health: `http://localhost:8080/api/health`
- search: `http://localhost:8080/api/search`

### 프론트 실행했음

```bash
cd frontend
npm run dev
```

- 화면 주소: `http://localhost:3000`
- 프론트 `/api` 요청은 백엔드 `8080`으로 rewrite됨.

## API 메모

### 검색 요청

```bash
curl -X POST http://localhost:8080/api/search \
  -H 'Content-Type: application/json' \
  -d '{
    "query": "조용하게 공부하기 좋은 카페",
    "mode": "HYBRID",
    "latitude": 37.5535,
    "longitude": 126.9221,
    "radiusKm": 6,
    "topK": 5
  }'
```

### 검색 응답에 들어감

- 장소 이름 들어감.
- 카테고리 들어감.
- 주소 들어감.
- 거리 들어감.
- 검색 근거 문장 들어감.
- 점수 정보 들어감.

## 최근 변경했음

- 서비스명 `Pero`로 맞췄음.
- 첫 화면 구조 단순화했음.
- 검색 기준 UI 단순화했음.
- 결과 카드 정보 줄였음.

## 다음 작업

1. 데이터 더 넣어야 함.
2. 검색 품질 평가셋 만들어야 함.
3. 검색 로그 저장 붙여야 함.
4. 배포 문서 정리해야 함.
5. OpenSearch 전환 검토해야 함.

## 참고 문서

- 아키텍처 자세한 내용은 `docs/architecture/기술스택_인프라_아키텍처_설계.md` 참고함.

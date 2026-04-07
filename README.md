# Pero / Lumo

`Pero` 저장소에서 개발 중인 `Lumo`는 리뷰 의미 분석과 위치 정보를 결합한 Geo-Semantic 장소 검색 졸업작품 프로토타입이다.

## 현재 구현 상태

- `Spring Boot` 백엔드
- `Next.js` 프론트엔드
- 샘플 장소/리뷰 데이터 기반 검색
- `KEYWORD / VECTOR / HYBRID` 검색 모드
- 거리 기반 점수 보정과 근거 문장 반환

현재 구현은 샘플 JSON 데이터와 실험용 `hashed embedding` 기반 검색기까지 완료된 상태다. 이후 단계별 발전 계획은 `docs/project-roadmap.md`를 기준으로 진행한다.

## 디렉토리 구조

- `backend/`: Spring Boot 검색 API
- `frontend/`: Next.js 검색 UI
- `docs/architecture/`: 기술 스택 및 인프라 설계 문서
- `docs/project-roadmap.md`: 단계별 발전 계획과 실행 로드맵
- `docs/proposals/`: 제안서 문서
- `docs/reports/weekly/`: 주간 보고서 PDF
- `scripts/`: 문서 생성 보조 스크립트

## 실행 방법

### 1. 백엔드 실행

```bash
cd backend
./gradlew bootRun
```

기본 주소:

- `http://localhost:8080/api/health`
- `http://localhost:8080/api/search`

### 2. 프론트엔드 실행

```bash
cd frontend
npm run dev
```

기본 주소:

- `http://localhost:3000`

Next.js rewrite가 `/api` 요청을 `http://localhost:8080`으로 전달한다. 개발 단계에서는 `3000`과 `5173` 포트를 모두 허용하도록 백엔드 CORS를 맞춰두었다.

## 예시 검색 요청

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

## 구현 메모

- 벡터 검색은 현재 주차에 맞춘 실험용 `hashed embedding` 방식으로 구현했다.
- 이후 실제 배포 단계에서는 `Sentence Transformers + OpenSearch k-NN` 구조로 확장하면 된다.

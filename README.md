# Pero

`Pero`는 리뷰 내용과 위치 정보를 같이 보는 장소 검색 졸업작품임.

## 지금 상태

- 검색 API 구현했음.
- 프론트 검색 화면 붙였음.
- 실제 지도 연동했음.
- 리뷰 근거 문장 반환했음.
- 지역/반경 기준 검색 붙였음.
- 데이터는 샘플 8건만 넣어둠.
- OpenSearch는 아직 안 붙였음.

## 실행

1. 백엔드 실행했음.

```bash
cd backend
./gradlew bootRun
```

2. 프론트 실행했음.

```bash
cd frontend
npm run dev
```

- 프론트 주소: `http://localhost:3000`
- 백엔드 health: `http://localhost:8080/api/health`
- 백엔드 search: `http://localhost:8080/api/search`

## 문서

- 통합 개발 문서: `docs/development.md`
- 로드맵 메모: `docs/project-roadmap.md`
- 아키텍처 참고: `docs/architecture/기술스택_인프라_아키텍처_설계.md`

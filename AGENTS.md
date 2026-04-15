# Pero Project Agents

이 문서는 `Pero` 졸업작품을 병렬로 진행할 때 사용할 서브에이전트 역할과 작업 경계를 정의한다.

## Shared Context

- 제품 목표: 자연어 질의 + 위치 정보를 기반으로 장소를 검색하고, 장소 메타데이터 기반 검색 근거를 보여준다.
- 현재 상태:
  - 백엔드: Spring Boot 기반 검색 API, 샘플 JSON 데이터 8건, KEYWORD / VECTOR / HYBRID 랭킹 실험 구현
  - 프론트엔드: Next.js 단일 페이지 검색 UI, `/api/search` 호출, 실제 지도 시각화
  - 문서: 아키텍처 초안과 주간보고서 존재, 실제 구현 로드맵은 `docs/project-roadmap.md` 기준
- 형상관리 규칙:
  - 개인 레포 작업은 `main -> origin`
  - 교수님 제출 작업은 `ksj -> prof`
  - 작업 중간 업로드는 커밋 메시지 `.`
  - 함수/모듈 단위 완료는 해당 이름으로 커밋
  - 화요일 또는 중간 단위 구현 완료 시 `ksj -> dev` PR
  - PR 제목은 짧고 결과 중심으로 적음
  - PR 제목과 description은 한국어로 적음
  - PR description은 변경 내용, 검증 내용만 짧게 적음

## Agent Roles

### 1. Planner Agent

- 목표: 우선순위, 범위, 데모 시나리오, 마일스톤 정의
- 입력: 현재 구현 상태, 지도교수 요구사항, 시연 일정
- 출력: 스프린트 목표, 작업 순서, PR 단위 정의
- 개입 시점: 방향이 흔들리거나 범위가 커질 때

### 2. Search Backend Agent

- 목표: 검색 API, 랭킹 로직, 요청 검증, 결과 스키마 고도화
- 담당 범위:
  - `backend/src/main/java/com/pero/search/controller/`
  - `backend/src/main/java/com/pero/search/service/`
  - `backend/src/main/java/com/pero/search/dto/`
- 완료 기준:
  - API 계약이 안정적일 것
  - 검색 결과 품질을 설명할 수 있을 것
  - 테스트가 추가될 것

### 3. Search Frontend Agent

- 목표: 검색 경험, 필터 UX, 지도 시각화, 결과 해석 UI 개선
- 담당 범위:
  - `frontend/src/app/`
  - `frontend/next.config.ts`
- 완료 기준:
  - 검색 흐름이 시연 가능할 것
  - 모바일/데스크톱 모두 깨지지 않을 것
  - 상태 표시(`loading`, `error`, `empty`)가 명확할 것

### 4. Data / ETL Agent

- 목표: 샘플 JSON을 넘어서 실제 시연 가능한 데이터셋과 적재 파이프라인 확보
- 담당 범위:
  - `backend/src/main/resources/data/`
  - 향후 `scripts/etl/` 또는 `data/` 디렉토리
- 완료 기준:
  - 데이터 출처와 전처리 방식이 문서화될 것
  - 재생성 가능한 적재 스크립트가 있을 것

### 5. Evaluation / QA Agent

- 목표: 검색 품질, 회귀 테스트, 데모 안정성 검증
- 담당 범위:
  - 검색 테스트 시나리오
  - API/프론트 smoke test
  - 검색 로그 및 정답셋 초안
- 완료 기준:
  - 대표 질의 세트와 기대 결과가 정의될 것
  - 변경 후 품질 저하를 빠르게 감지할 수 있을 것

### 6. Infra / Demo Agent

- 목표: 실행 환경 통합, 배포, 시연 운영 문서 정리
- 담당 범위:
  - Docker Compose
  - 환경 변수 정리
  - 실행 문서, 데모 체크리스트, PR 릴리즈 노트
- 완료 기준:
  - 처음 받는 사람도 실행 가능할 것
  - 시연 직전 점검 절차가 짧고 명확할 것

## Working Protocol

1. 한 번에 하나의 데모 목표만 잡는다.
2. 검색 품질 개선보다 먼저 UI 시연 완성도를 확보한다.
3. 데이터 확장은 반드시 재현 가능한 스크립트와 함께 간다.
4. PR 하나에는 하나의 명확한 결과만 담는다.
5. 문서 변경도 구현과 같이 간다. 설명이 없는 기능은 남기지 않는다.

## Immediate Assignment Order

1. `Search Frontend Agent`: 실제 지도와 필터 기반 시연 UI 완성
2. `Search Backend Agent`: 검색 API 응답 확장, 정렬/필터 정책 정리
3. `Data / ETL Agent`: 데이터셋 50~100건 수준으로 확대
4. `Evaluation / QA Agent`: 대표 질의셋과 기대 결과 정의
5. `Infra / Demo Agent`: docker compose, env, 실행 문서 정리

# Pero Project Roadmap

## Current Baseline

현재 프로젝트는 "검색 실험이 되는 프로토타입" 단계다.

- 프론트엔드는 검색 입력, 모드 선택, 위치 좌표, 결과 카드, 가상 좌표 분포 뷰까지 한 페이지에 구현돼 있다: `frontend/src/app/page.tsx`
- 프론트는 `/api/:path*`를 로컬 Spring Boot로 rewrite 한다: `frontend/next.config.ts`
- 백엔드는 KEYWORD / VECTOR / HYBRID 검색과 거리 보정을 메모리 기반으로 수행한다: `backend/src/main/java/com/lumo/search/service/SearchService.java`
- 데이터는 샘플 장소 8건으로 제한돼 있다: `backend/src/main/resources/data/places.json`
- 백엔드 테스트와 프론트 lint는 현재 통과한다.

즉, "아이디어 검증"은 됐지만 "졸업작품 완성도"로 가기 위한 핵심 축은 아직 비어 있다.

## Main Gaps

1. 실제 지도가 없다. 현재는 좌표를 점으로 뿌리는 가상 뷰만 있다.
2. 데이터가 너무 적다. 8건으로는 검색 품질과 시연 설득력이 약하다.
3. 검색 품질 평가 체계가 없다. 질의셋, 기대 결과, 로그가 아직 없다.
4. 검색 엔진이 메모리 기반 실험 구현이라 문서상의 OpenSearch 구조와 차이가 크다.
5. 배포와 시연 루틴이 정리되지 않았다.

## Development Principle

1. 먼저 "보여줄 수 있는 제품"을 만든다.
2. 그 다음 "검색 품질"을 끌어올린다.
3. 마지막에 "배포/시연/문서"를 마감한다.

이 순서가 맞다. 지금 단계에서 OpenSearch부터 붙이면 데모 완성도가 늦어지고, UI부터 완성하면 화요일 PR과 중간 시연에 바로 쓸 수 있다.

## Milestone 1: Demo-Ready MVP

목표: 교수님 앞에서 검색 시나리오를 안정적으로 시연할 수 있게 만든다.

### Scope

- Kakao Maps SDK 또는 동등한 실제 지도 컴포넌트 연동
- 검색 결과 카드와 지도 마커 동기화
- 카테고리 / 태그 / 반경 필터 UI 추가
- 결과 정렬 이유와 근거 문장 가독성 개선
- API 에러, empty, loading 상태 정리
- 프론트/백엔드 실행 가이드 단순화

### Exit Criteria

- 대표 질의 5개 이상이 시연 중 끊기지 않고 동작
- 모바일과 데스크톱에서 기본 레이아웃 유지
- 검색 결과와 지도 인터랙션이 자연스럽게 연결

## Milestone 2: Retrieval Quality Upgrade

목표: 검색 결과가 "프로토타입"이 아니라 "설명 가능한 검색 시스템"처럼 보이게 만든다.

### Scope

- 데이터셋 50~100건 이상 확보
- 장소 / 리뷰 전처리 스크립트 추가
- 대표 질의셋과 기대 top result 정의
- 검색 로그 수집
- 랭킹 파라미터 조정 근거 문서화
- 가능하면 OpenSearch 기반 인덱싱 구조로 전환 시작

### Exit Criteria

- 대표 질의셋에서 결과 일관성 확보
- 품질 비교 전/후를 문서로 설명 가능
- 데이터 재생성이 가능

## Milestone 3: Graduation-Ready Delivery

목표: 제출과 시연, 인수인계까지 가능한 상태로 마감한다.

### Scope

- Docker Compose 기반 실행
- `.env.example` 정리
- PR/브랜치 운영 규칙 고정
- 실행 문서, 데모 스크립트, 장애 대응 체크리스트 작성
- 스크린샷/영상 캡처용 시연 시나리오 정리

### Exit Criteria

- 새 환경에서 재현 가능
- 발표 직전 체크리스트로 점검 가능
- PR과 문서가 현재 코드 상태를 반영

## Next 10 Tasks

1. 실제 지도 SDK 도입 여부 결정 후 지도 컴포넌트 추가
2. 검색 결과 카드 선택 시 해당 마커 강조
3. 태그/카테고리/거리 필터 UI 추가
4. 검색 API 응답에 정렬 이유 설명 필드 추가
5. 질의 로그 저장 구조 설계
6. 샘플 데이터 확장용 수집/정제 스크립트 초안 작성
7. 대표 질의 20개와 기대 결과 표 작성
8. 백엔드 검색 로직 단위 테스트 추가
9. Docker Compose 초안 작성
10. 시연 스크립트와 화요일 PR 템플릿 정리

## Weekly Operating Rhythm

- 월요일: 이번 주 데모 목표 확정
- 화요일: `ksj -> dev` PR 생성
- 수요일~목요일: 검색 품질 / 데이터 / UI 보완
- 금요일: 문서와 데모 시나리오 정리

## Immediate Recommendation

다음 작업은 `Milestone 1`부터 들어가는 게 맞다. 첫 착수 순서는 아래가 가장 효율적이다.

1. 프론트 지도 연동
2. 결과-마커 상호작용
3. 필터 UI
4. 검색 응답 설명 필드 정리
5. 데이터 확장 준비

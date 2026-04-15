# Pero 5주차 진행 보고서 (2026-04-07 ~ 2026-04-13)

## 1. 주차 개요
주제는 기존 리뷰 기반 접근에서 장소 메타데이터 기반의 자연어 + 위치 기반 검색으로 재정의되었고,  
5주차에서는 **데모 완성도와 검색 품질 동작의 일관성**을 최우선으로 보강하였다.

- 프로젝트명: Pero
- 핵심 목표: 자연어 질의와 위치 정보를 활용한 장소 탐색 UI + 검색 근거(증거) 제공
- 진행 기간: 2026-04-07 ~ 2026-04-13
- 팀 구성: 개인 진행

## 2. 이번 주 수행 내용

### 2.1 백엔드 검색 로직 정비
- 검색 API 엔드포인트(`/api/search`)의 핵심 파이프라인을 고도화하여 아래를 반영함.
  - 키워드/벡터/특징 점수 기반 하이브리드 랭킹
  - 모드별 가중치 적용: KEYWORD / VECTOR / HYBRID
  - 거리 제약(`latitude`, `longitude`, `radiusKm`)이 없을 때 지역 편중 완화 로직 추가
- 위치 미지정 검색 시 `diversifyByDistrict`(지역 라운드로빈)를 적용해 특정 지역 집중 현상 완화.
- 응답 포맷은 기존 `SearchResponse` 기준 유지하여 프론트 연동성 확보.

관련 파일
- [backend/src/main/java/com/pero/search/service/SearchService.java](/Users/ksj/Desktop/02_Work/Projects/Pero/backend/src/main/java/com/pero/search/service/SearchService.java)
- [backend/src/main/java/com/pero/search/controller/SearchController.java](/Users/ksj/Desktop/02_Work/Projects/Pero/backend/src/main/java/com/pero/search/controller/SearchController.java)
- [backend/src/main/java/com/pero/search/dto/SearchRequest.java](/Users/ksj/Desktop/02_Work/Projects/Pero/backend/src/main/java/com/pero/search/dto/SearchRequest.java)

### 2.2 데이터셋 확장
- Kakao Local API 기반 스크립트를 통해 초기 샘플(8건)에서 100건 확대로 전환함.
- 수집 대상 지역: 홍대입구/연남/성수/잠실/서촌
- 각 지역 균형 배분(현재 20건씩)으로 검색 지도에서 지역 편향 테스트가 가능하도록 보강.

관련 파일
- [scripts/etl/kakao_places_to_pero.py](/Users/ksj/Desktop/02_Work/Projects/Pero/scripts/etl/kakao_places_to_pero.py)
- [backend/src/main/resources/data/places.json](/Users/ksj/Desktop/02_Work/Projects/Pero/backend/src/main/resources/data/places.json)
- [docs/data-etl.md](/Users/ksj/Desktop/02_Work/Projects/Pero/docs/data-etl.md)

### 2.3 프론트엔드 UI/UX 보강
- 네비게이션+리스트 패널을 기본 비노출 처리하고 검색/마커 이벤트 시에만 표시되도록 수정.
- 기본 화면은 지도 중심으로 변경하여 시연 시 바로 공간 탐색이 가능하도록 개선.
- 검색 결과 카드, 마커, 근거 패널 연동을 유지한 채 인터랙션 중심 흐름 정리.

관련 파일
- [frontend/src/app/page.tsx](/Users/ksj/Desktop/02_Work/Projects/Pero/frontend/src/app/page.tsx)
- [frontend/src/app/globals.css](/Users/ksj/Desktop/02_Work/Projects/Pero/frontend/src/app/globals.css)
- [frontend/src/app/components/search-map.tsx](/Users/ksj/Desktop/02_Work/Projects/Pero/frontend/src/app/components/search-map.tsx)

## 3. 산출물 요약
- 검색 API 동작 개선: 모드별 하이브리드 랭킹 가중치 반영
- 데이터셋 규모: 100건
- 프론트 핵심 UX 변경: 최초 화면 지도 전체 노출 + 이벤트 기반 사이드/리스트 노출
- 지역 다양성 보정 로직 도입으로 위치 미지정 검색의 편중 감소
- 문서 보강: ETL 절차/개발 통합 흐름 정리

## 4. 문제점 및 개선 사항
- 실제 검색 품질은 데이터의 정합도에 강하게 의존.
  - 해결: ETL 재수집 규칙 문서화, 핵심 후보 수동 검수 필요.
- 검색 모드별 점수 해석은 구현 완료했으나, 정량 평가셋은 미완성.
  - 해결: 6주차부터 질의셋/평가 로그 파이프라인 구축 예정.

## 5. 6주차 계획
1. 핵심 데모 후보 20건 수동 검수 및 정답셋 초안 작성
2. 대표 질의셋 30~50건 정의 후 검색 결과 정합성 점검
3. `search` 요청/응답 로그 기록 설계(최소 로그 항목: 쿼리, 모드, 위치, topK, 반환점수)
4. 실행/시연 체크리스트 정리(개발자 입출력, 크래시 대응 절차 포함)

## 6. 결론
5주차는 **검색 엔진 동작의 정합성 강화와 데모 완성도 개선**을 중심으로 진행되었다.  
백엔드 랭킹 개선, 데이터 보강, UI 흐름 정리를 통해 다음 주차에서 평가용 시나리오와 품질 지표 실험을 바로 붙일 수 있는 상태가 되었다.

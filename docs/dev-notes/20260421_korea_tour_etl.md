# 2026-04-21 KorTour ETL 전환 및 스마트서울 전환 준비 노트

## 배경

- 기존 `backend/src/main/resources/data/places.json`은 카카오 임시 스크립트(`kakao_places_to_pero.py`) 기반 샘플에 의존해 데모 데이터 성격이 강했음.
- 발표 직전에도 "데모용 더미 -> 실제 API 기반 데이터"로 이동이 필요했고, 시연 중 캐시 소스 표시/폴백 동작이 명확해야 했음.
- 또한 Smart Seoul 연동은 아직 승인 전이라, 승인 전후 토글 동작 테스트까지 준비 가능한 형태의 공급자 계약이 필요했음.

## 이번 변경

### 1) KorTour ETL 스크립트 정합

- 실제 동기화 스크립트를 `scripts/etl/sync_places.py`로 표준화.
- 실제 수집은 KorService2 `locationBasedList2`를 사용.
- 정규화된 캐시 대상:
  - `backend/src/main/resources/data/places.json`
  - `backend/src/main/resources/data/places.json.meta.json`
- `PlaceSeed` 매핑 및 정합:
  - `id`: `koreaTour-{contentid}`
  - `district`/`address`/`roadAddress`: KorService2 주소 기반으로 정규화
  - `tags`, `searchHints`: 검색 시나리오(조용한, 반려동물, 식사, 산책 등)에 유효한 동의어/문맥 보강
- 공백/좌표/주소 무효 레코드 제거 규칙 유지:
  - 좌표 파싱 실패
  - 주소 길이 부족 또는 행정/도로 키워드 부재
  - 대한민국 좌표 범위 밖
- 중복 규칙:
  - `contentid` 중복은 교체/중복 카운트 처리
  - 동일 이름·주소·좌표 라운드 조합은 추가 중복 제거

### 2) 운영/폴백 요구사항 반영

- 캐시 미존재/파싱 실패 시 서버 시작 실패 없이 `cache-missing`, `parse-error` 상태를 전달하는 기존 provider 체인을 유지.
- provider 순서를 `koreaTour,smartSeoul` 기본값으로 둠.
- Smart Seoul 토글은 준비되었을 때 전환 가능한 모듈 상태를 유지:
  - 현재는 `smartSeoul` 콜렉터 비활성
  - 승인 뒤 `pero.providers.smartSeoul.enabled=true` + 캐시 존재 시 우선 사용되는 흐름 검증 대상

### 3) GitHub Actions 동기화 파이프라인

- `.github/workflows/sync-koreatour-cache.yml` 추가
  - 수동 실행 + 주간(일요일 03:00 KST, `0 18 * * 0`) 동기화
- 변경 파일(`places.json`, `places.json.meta.json`)이 있을 때 자동으로 갱신 브랜치 PR 생성

### 4) backend 테스트/스위치 대비

- provider 레지스트리/포함된 통합 테스트를 통해:
  - smart cache missing 시 koreaTour 폴백
  - smartSeoul 우선순위 시 smart 데이터 선출
  - source 메타 노출(`providerId`, `providerName`, `status`, `count`) 검증을 강화

## 실행/검증

```bash
# 드라이런(요약)
python3 scripts/etl/sync_places.py --dry-run --max-places 60 --region-target 8 --pause 0.0

# 실제 캐시 갱신
python3 scripts/etl/sync_places.py --max-places 120 --region-target 10 --pause 0.0

# 주간 자동화
Workflow: Sync KoreaTour Places Cache
```

### 실행 결과 요약

- dry-run 결과:
  - `count=60`, `status=ok`
  - `requestCount=8`, `rawItemCount=400`, `acceptedCount=60`
  - 중복 드롭/파싱 실패 없음
- 실제 write 결과:
  - `count=120`
  - 생성 `status=ok`
  - 생성 파일:
    - `backend/src/main/resources/data/places.json`
    - `backend/src/main/resources/data/places.json.meta.json`
- 메타 예시:
  - `providerId: koreaTour`
  - `providerName: 한국관광공사 API 동기화 캐시`
  - `count: 120`

## 영향 파일

- `scripts/etl/sync_places.py` (최종 진입점)
- `scripts/etl/korservice2_to_pero.py` (수집/정규화 엔진)
- `scripts/etl/pero_etl_common.py` (공통 헬퍼, 유지)
- `.github/workflows/sync-koreatour-cache.yml` (주기 동기화)
- `backend/src/main/resources/data/places.json`
- `backend/src/main/resources/data/places.json.meta.json`
- `backend/src/main/java/com/pero/search/data/*` (공급자/레지스트리)
- `backend/src/test/java/com/pero/search/controller/*` (provider 전환 테스트)
- `docs/data-etl.md`, `docs/development.md`, `docs/dev-notes/20260421_korea_tour_etl.md`

## 후속 작업

- Smart Seoul 승인/심사 후 `scripts/etl/sync_places.py` 또는 별도 스크립트로 smart 캐시 동기화 엔트리 추가
- 승인 후 `pero.providers.smartSeoul.enabled=true`에서 검색/places source 메타 전환 테스트 자동화 확장
- 쿼리별 데모 시나리오(조용한 카페, 반려동물 동반, 야간 산책 등) 실검증

## 커밋/PR

- commit:
  - `feat(etl): 한국관광공사 KorService2 기반 places 캐시 파이프라인 추가`
  - `feat(ci): KorService2 캐시 주기 동기화 워크플로 추가`
  - `docs: data-etl/개발노트 업데이트`
- PR:
  - 브랜치 기준: `chore/koreatour-etl`

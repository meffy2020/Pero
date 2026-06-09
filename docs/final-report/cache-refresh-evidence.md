# Pero 캐시 갱신 및 iOS 확인 증거

## 데이터 갱신

- 갱신 기준일: 2026-06-10
- 한국관광공사 `searchFestival2` ETL로 오늘 이후 행사/축제 캐시 보강
- 축제 후보: 184개
- 현재 진행 중 축제: 36개
- 과거 행사: 0개
- 제목에 `2025` 포함된 축제 후보: 0개
- 식당 후보: Kakao Local 캐시만 사용
- 장소 후보: Smart Seoul + KoreaTour + Kakao 캐시 병합 후 지도 bounds/반경 기준 제한

## API 확인 결과

- 서울 시청권 축제: 30개 반환, `2025=false`, `페인터즈=false`
- 전국 축제: 30개 반환, `2025=false`, `페인터즈=false`
- 노원/하계동 식당: 20개 반환, `source=kakaoLocal`
- 서울 시청권 장소: 20개 반환, Smart Seoul/KoreaTour 혼합

## iOS 확인 스크린샷

- `docs/final-report/screenshots/pero-ios-app-1.png`
- `docs/final-report/screenshots/pero-ios-app-2.png`
- `docs/final-report/screenshots/pero-ios-app-3.png`
- `docs/final-report/screenshots/pero-ios-app-4.png`
- `docs/final-report/screenshots/pero-ios-app-5.png`
- `docs/final-report/screenshots/pero-ios-app-6.png`
- `docs/final-report/screenshots/pero-ios-app-7.png`
- `docs/final-report/screenshots/pero-ios-app-8.png`

## iPhone 설치 상태

- 실제 iPhone `com.pero.ios` 빌드/설치 완료
- 실행은 iOS 보안 정책상 개발자 프로파일 신뢰가 필요해 차단됨
- 시뮬레이터에서는 동일 터널 백엔드로 앱 실행 후 스크린샷 저장 완료

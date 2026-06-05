# Kakao Local REST API 연동 메모

## 적용 원칙

- iOS 앱에는 Kakao **네이티브 앱 키**만 둔다. 장소 검색용 **REST API 키는 백엔드 환경 변수**로만 넣는다.
- iOS는 현재 지도 화면의 사각 영역을 백엔드로 보낸다.
- 백엔드는 Kakao Local REST API를 호출한 뒤 Pero의 장소 응답 모델로 변환한다.

## iOS -> 백엔드 요청 형태

```http
GET /api/kakao/places?mode=restaurant&rect=126.90,37.45,127.10,37.62
```

`rect`는 현재 화면 사각형이다.

```text
minLongitude,minLatitude,maxLongitude,maxLatitude
```

현재 iOS 앱은 Kakao Maps SDK의 카메라 정지 이벤트에서 화면 네 모서리 좌표를 읽어 이 범위를 계산한다.

## 백엔드 -> Kakao Local 호출

### 식당/카페/관광명소

```bash
curl -G 'https://dapi.kakao.com/v2/local/search/category.json' \
  -H 'Authorization: KakaoAK ${KAKAO_REST_API_KEY}' \
  --data-urlencode 'category_group_code=FD6' \
  --data-urlencode 'rect=126.90,37.45,127.10,37.62' \
  --data-urlencode 'size=15'
```

추천 매핑:

| Pero mode | Kakao 호출 |
| --- | --- |
| 관광지 | `category_group_code=AT4` |
| 식당 | `category_group_code=FD6` |
| 카페까지 포함 | `FD6` + `CE7` 두 번 호출 후 합치기 |
| 축제 | 카테고리 코드가 별도로 없으므로 keyword API에서 `query=축제` 또는 KoreaTour 데이터 사용 |

### 축제 키워드 검색

```bash
curl -G 'https://dapi.kakao.com/v2/local/search/keyword.json' \
  -H 'Authorization: KakaoAK ${KAKAO_REST_API_KEY}' \
  --data-urlencode 'query=축제' \
  --data-urlencode 'rect=126.90,37.45,127.10,37.62' \
  --data-urlencode 'size=15'
```

## 백엔드 환경 변수

```bash
KAKAO_REST_API_KEY=...
```

주의: 지금 iOS 지도에 쓰는 네이티브 앱 키와 REST API 키는 같은 값이 아니다. 카카오 개발자 콘솔의 `[앱] > [앱 키] > REST API 키`를 서버에 넣어야 한다.

## 공식 문서 기준

- Kakao Local REST API는 REST API 키를 `Authorization: KakaoAK ${REST_API_KEY}` 헤더에 담아 호출한다.
- 카테고리 검색은 `/v2/local/search/category.json`, 키워드 검색은 `/v2/local/search/keyword.json`이다.
- 카테고리 검색은 `rect` 파라미터로 지도 화면 사각형 내 제한 검색을 지원한다.

#!/usr/bin/env python3
"""Collect Kakao Local keyword results and convert them to Pero places.json."""

from __future__ import annotations

import argparse
import json
import os
from datetime import datetime, timezone, timedelta
import time
import urllib.parse
import urllib.request
from pathlib import Path
from typing import Any


ROOT_DIR = Path(__file__).resolve().parents[2]
DEFAULT_OUTPUT = ROOT_DIR / "backend/src/main/resources/data/places.kakao.json"
KAKAO_KEYWORD_URL = "https://dapi.kakao.com/v2/local/search/keyword.json"
KAKAO_MAX_RADIUS_METERS = 20000

TARGETS = [
    {
        "area": "서울",
        "latitude": 37.5665,
        "longitude": 126.9780,
        "radius": "30000",
        "keywords": ["맛집", "한식", "분식", "백반", "고기집", "음식점", "국밥", "찌개"],
    },
    {
        "area": "서울 노원구",
        "latitude": 37.6542,
        "longitude": 127.0568,
        "radius": "9000",
        "keywords": ["노원역 맛집", "하계역 맛집", "하계동 식당", "중계동 맛집", "공릉역 맛집", "공릉동 식당", "상계동 맛집", "노원구 한식", "노원구 분식", "노원구 음식점"],
    },
    {
        "area": "서울 노원구 하계동",
        "latitude": 37.6362,
        "longitude": 127.0679,
        "radius": "3500",
        "keywords": ["하계역 맛집", "하계동 맛집", "하계동 한식", "하계동 분식", "하계동 고기집", "하계동 음식점"],
    },
    {
        "area": "서울 노원구 공릉동",
        "latitude": 37.6259,
        "longitude": 127.0730,
        "radius": "3500",
        "keywords": ["공릉역 맛집", "공릉동 맛집", "공릉동 한식", "공릉동 분식", "공릉동 고기집", "공릉동 음식점"],
    },
    {
        "area": "서울 마포구",
        "latitude": 37.5663,
        "longitude": 126.9019,
        "radius": "9000",
        "keywords": ["마포구 맛집", "홍대 맛집", "합정 맛집", "망원동 맛집", "연남동 맛집", "마포구 음식점"],
    },
    {
        "area": "서울 강남구",
        "latitude": 37.5172,
        "longitude": 127.0473,
        "radius": "9000",
        "keywords": ["강남역 맛집", "역삼동 맛집", "신사동 맛집", "압구정 맛집", "강남구 한식", "강남구 음식점"],
    },
    {
        "area": "서울 종로구",
        "latitude": 37.5729,
        "longitude": 126.9794,
        "radius": "8000",
        "keywords": ["종로 맛집", "을지로 맛집", "광화문 맛집", "인사동 맛집", "종로구 한식", "종로구 음식점"],
    },
    {
        "area": "부산",
        "latitude": 35.1796,
        "longitude": 129.0756,
        "radius": "30000",
        "keywords": ["맛집", "한식", "분식", "고기집", "음식점", "국밥"],
    },
    {
        "area": "인천",
        "latitude": 37.4563,
        "longitude": 126.7052,
        "radius": "25000",
        "keywords": ["맛집", "한식", "분식", "음식점", "국밥", "고기집"],
    },
    {
        "area": "대구",
        "latitude": 35.8714,
        "longitude": 128.6017,
        "radius": "25000",
        "keywords": ["맛집", "한식", "분식", "레스토랑", "음식점", "고기집"],
    },
    {
        "area": "광주",
        "latitude": 35.1595,
        "longitude": 126.8526,
        "radius": "25000",
        "keywords": ["맛집", "한식", "분식", "음식점", "국밥", "고기집"],
    },
    {
        "area": "대전",
        "latitude": 36.3504,
        "longitude": 127.3845,
        "radius": "25000",
        "keywords": ["맛집", "한식", "분식", "음식점", "국밥", "고기집"],
    },
    {
        "area": "울산",
        "latitude": 35.5384,
        "longitude": 129.3114,
        "radius": "20000",
        "keywords": ["맛집", "한식", "분식", "카페", "브런치", "베이커리"],
    },
    {
        "area": "세종",
        "latitude": 36.4800,
        "longitude": 127.2890,
        "radius": "22000",
        "keywords": ["맛집", "한식", "분식", "음식점", "국밥", "고기집"],
    },
    {
        "area": "제주",
        "latitude": 33.4996,
        "longitude": 126.5312,
        "radius": "25000",
        "keywords": ["맛집", "한식", "분식", "음식점", "국밥", "고기집"],
    },
]

SEOUL_DISTRICTS = [
    ("서울 강남구", 37.5172, 127.0473),
    ("서울 강동구", 37.5301, 127.1238),
    ("서울 강북구", 37.6396, 127.0257),
    ("서울 강서구", 37.5509, 126.8495),
    ("서울 관악구", 37.4784, 126.9516),
    ("서울 광진구", 37.5384, 127.0823),
    ("서울 구로구", 37.4955, 126.8877),
    ("서울 금천구", 37.4569, 126.8955),
    ("서울 노원구", 37.6542, 127.0568),
    ("서울 도봉구", 37.6688, 127.0471),
    ("서울 동대문구", 37.5744, 127.0396),
    ("서울 동작구", 37.5124, 126.9393),
    ("서울 마포구", 37.5663, 126.9019),
    ("서울 서대문구", 37.5791, 126.9368),
    ("서울 서초구", 37.4836, 127.0327),
    ("서울 성동구", 37.5633, 127.0369),
    ("서울 성북구", 37.5894, 127.0167),
    ("서울 송파구", 37.5145, 127.1059),
    ("서울 양천구", 37.5169, 126.8664),
    ("서울 영등포구", 37.5264, 126.8963),
    ("서울 용산구", 37.5326, 126.9905),
    ("서울 은평구", 37.6027, 126.9291),
    ("서울 종로구", 37.5729, 126.9794),
    ("서울 중구", 37.5636, 126.9976),
    ("서울 중랑구", 37.6063, 127.0925),
]

for area, latitude, longitude in SEOUL_DISTRICTS:
    TARGETS.append(
        {
            "area": area,
            "latitude": latitude,
            "longitude": longitude,
            "radius": "6500",
            "keywords": [
                f"{area} 맛집",
                f"{area} 한식",
                f"{area} 분식",
                f"{area} 고기집",
                f"{area} 일식",
                f"{area} 중식",
                f"{area} 음식점",
            ],
        }
    )


RESTAURANT_ALLOW_WORDS = [
    "음식", "음식점", "식당", "한식", "중식", "중국", "일식", "일본", "양식", "분식", "고기", "육류", "레스토랑",
    "국밥", "찌개", "전골", "국수", "칼국수", "냉면", "초밥", "롤", "회", "해물", "생선", "닭", "치킨",
    "족발", "보쌈", "곱창", "막창", "갈비", "순대", "떡볶이", "돈까스", "우동", "삼계탕", "감자탕", "곰탕",
    "설렁탕", "해장국", "추어", "두부", "피자", "버거", "맥도날드", "롯데리아", "맘스터치", "버거킹",
    "김밥", "만두", "죽", "도시락", "라면", "베트남", "태국", "멕시칸", "브라질", "이탈리안", "파스타",
    "구내식당", "한정식", "오리", "장어", "조개", "복어", "아구", "불고기", "수제비", "샤브", "백반",
]

RESTAURANT_DENY_WORDS = [
    "카페", "커피", "스타벅스", "투썸", "컴포즈", "메가", "빽다방", "이디야", "할리스", "엔제리너스", "커피빈",
    "파스쿠찌", "폴바셋", "쥬씨", "공차", "팀홀튼", "매머드", "텐퍼센트", "카페인", "다방", "전통찻집",
    "디저트", "베이커리", "제과", "파리바게뜨", "뚜레쥬르", "던킨", "도넛", "아이스크림", "배스킨", "설빙",
    "브런치", "샐러드", "샌드위치", "주스", "쥬스", "생과일", "요거트", "빙수", "케이크", "마카롱",
    "술집", "호프", "요리주점", "와인바", "칵테일바", "뮤직바", "포장마차", "이벤트기획", "대행",
]


def is_restaurant_document(place_name: str, category_name: str, keyword: str) -> bool:
    haystack = f"{place_name} {category_name} {keyword}"
    if any(word in haystack for word in RESTAURANT_DENY_WORDS):
        return False
    return any(word in haystack for word in RESTAURANT_ALLOW_WORDS)

def load_env(path: Path) -> None:
    if not path.exists():
        return

    for raw_line in path.read_text(encoding="utf-8").splitlines():
        line = raw_line.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        key, value = line.split("=", 1)
        os.environ.setdefault(key.strip(), value.strip().strip('"').strip("'"))


def kakao_radius(value: Any) -> str:
    try:
        radius = int(value)
    except (TypeError, ValueError):
        radius = KAKAO_MAX_RADIUS_METERS
    return str(max(0, min(radius, KAKAO_MAX_RADIUS_METERS)))


def request_keyword(api_key: str, keyword: str, target: dict[str, Any], page: int) -> dict[str, Any]:
    params = {
        "query": keyword,
        "x": str(target["longitude"]),
        "y": str(target["latitude"]),
        "radius": kakao_radius(target.get("radius")),
        "size": "15",
        "page": str(page),
        "sort": "distance",
    }
    url = f"{KAKAO_KEYWORD_URL}?{urllib.parse.urlencode(params)}"
    request = urllib.request.Request(url, headers={"Authorization": f"KakaoAK {api_key}"})

    with urllib.request.urlopen(request, timeout=12) as response:
        return json.loads(response.read().decode("utf-8"))


def category_tags(category_name: str, keyword: str) -> list[str]:
    source = f"{category_name} {keyword}"
    tags: list[str] = []

    rules = [
        ("북카페", ["조용한", "독서", "카공", "혼자", "차분한"]),
        ("스터디", ["공부", "집중", "노트북", "작업", "조용한"]),
        ("애견", ["반려동물", "애견", "펫", "동반", "산책"]),
        ("반려", ["반려동물", "애견", "펫", "동반", "산책"]),
        ("키즈", ["가족", "아이", "유아", "주말", "넓은좌석"]),
        ("패밀리", ["가족", "아이", "주말", "넓은좌석", "식사"]),
        ("한식", ["식당", "식사", "한식", "가족", "모임"]),
        ("분식", ["식당", "식사", "분식", "간단한", "혼밥"]),
        ("고기", ["식당", "식사", "고기", "모임", "저녁"]),
        ("일식", ["식당", "식사", "일식", "데이트", "모임"]),
        ("중식", ["식당", "식사", "중식", "모임", "점심"]),
        ("양식", ["식당", "식사", "양식", "데이트", "모임"]),
        ("맛집", ["식당", "식사", "맛집", "근처", "추천"]),
        ("음식점", ["식당", "식사", "음식점", "근처", "추천"]),
        ("음식", ["식사", "모임", "주말", "가족", "데이트"]),
    ]

    for needle, values in rules:
        if needle in source:
            tags.extend(values)

    if not tags:
        tags.extend(["장소", "근처", "방문", "탐색", "추천"])

    deduped: list[str] = []
    for tag in tags:
        if tag not in deduped:
            deduped.append(tag)
    return deduped[:6]


def make_summary(place_name: str, category_name: str, area: str, tags: list[str]) -> str:
    category = category_name.split(">")[-1].strip() or "장소"
    if "조용한" in tags or "공부" in tags:
        return f"{area} 인근의 {category}로, 조용히 머무르거나 작업하기 좋은 후보입니다."
    if "반려동물" in tags:
        return f"{area} 인근의 {category}로, 반려동물 동반 방문 맥락에 맞는 장소입니다."
    if "가족" in tags or "아이" in tags:
        return f"{area} 인근의 {category}로, 가족이나 아이와 함께 방문하기 좋은 후보입니다."
    if "식사" in tags:
        return f"{area} 인근의 {category}로, 식사와 모임에 적합한 장소입니다."
    if "데이트" in tags:
        return f"{area} 인근의 {category}로, 분위기 있는 방문 목적에 맞는 장소입니다."
    return f"{area} 인근의 {category}로, 현재 위치 기반 장소 탐색 후보입니다."


def make_hints(place_name: str, category_name: str, area: str, tags: list[str]) -> list[str]:
    hints = [
        f"{area} 주변에서 {category_name.split('>')[-1].strip() or '장소'} 유형으로 검색된 장소입니다.",
        f"{place_name}의 카테고리와 위치 정보를 기반으로 추천 후보에 포함했습니다.",
    ]

    if "조용한" in tags or "공부" in tags:
        hints.append("조용한 체류, 공부, 노트북 작업 같은 자연어 질의와 연결됩니다.")
    elif "반려동물" in tags:
        hints.append("반려동물 동반, 애견, 펫 관련 질의와 연결됩니다.")
    elif "가족" in tags or "아이" in tags:
        hints.append("아이 동반, 가족 식사, 주말 방문 질의와 연결됩니다.")
    elif "식사" in tags:
        hints.append("식사, 맛집, 근처 음식점 질의와 연결됩니다.")
    else:
        hints.append("분위기, 휴식, 근처 방문 같은 탐색형 질의와 연결됩니다.")

    return hints


def to_place(document: dict[str, Any], target: dict[str, Any], keyword: str) -> dict[str, Any] | None:
    try:
        latitude = float(document["y"])
        longitude = float(document["x"])
    except (KeyError, TypeError, ValueError):
        return None

    place_name = document.get("place_name", "").strip()
    if not place_name:
        return None

    category_name = document.get("category_name", "").strip()
    if not is_restaurant_document(place_name, category_name, keyword):
        return None
    tags = category_tags(category_name, keyword)
    address = document.get("address_name", "").strip()
    road_address = document.get("road_address_name", "").strip() or address
    kakao_id = document.get("id", "").strip()

    return {
        "id": f"kakao-{kakao_id or abs(hash((place_name, latitude, longitude)))}",
        "name": place_name,
        "category": category_name.split(">")[-1].strip() or keyword,
        "district": target["area"],
        "address": address,
        "roadAddress": road_address,
        "latitude": latitude,
        "longitude": longitude,
        "summary": make_summary(place_name, category_name, target["area"], tags),
        "tags": tags,
        "searchHints": make_hints(place_name, category_name, target["area"], tags),
    }


def collect(api_key: str, max_places: int, pause_seconds: float) -> list[dict[str, Any]]:
    places_by_key: dict[str, dict[str, Any]] = {}
    per_target_limit = max(1, max_places // len(TARGETS))

    for target in TARGETS:
        target_count = 0
        for keyword in target["keywords"]:
            if target_count >= per_target_limit:
                break
            for page in range(1, 4):
                if target_count >= per_target_limit:
                    break
                payload = request_keyword(api_key, keyword, target, page)
                for document in payload.get("documents", []):
                    place = to_place(document, target, keyword)
                    if place is None:
                        continue
                    key = place["id"]
                    if key not in places_by_key:
                        places_by_key[key] = place
                        target_count += 1
                    if len(places_by_key) >= max_places:
                        return list(places_by_key.values())
                    if target_count >= per_target_limit:
                        break

                if payload.get("meta", {}).get("is_end", True):
                    break
                time.sleep(pause_seconds)
            time.sleep(pause_seconds)

    return list(places_by_key.values())


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--env", default=str(ROOT_DIR / ".env"), help="Path to .env file")
    parser.add_argument("--output", default=str(DEFAULT_OUTPUT), help="Output places.json path")
    parser.add_argument("--max-places", type=int, default=100, help="Maximum places to write")
    parser.add_argument("--pause", type=float, default=0.12, help="Delay between API calls")
    parser.add_argument("--no-meta", action="store_true", help="Skip metadata sidecar generation")
    parser.add_argument("--dry-run", action="store_true", help="Print count and sample without writing")
    args = parser.parse_args()

    load_env(Path(args.env))
    api_key = os.environ.get("KAKAO_REST_API_KEY")
    if not api_key:
        raise SystemExit("KAKAO_REST_API_KEY is missing. Add it to .env.")

    places = collect(api_key, args.max_places, args.pause)
    if args.dry_run:
        print(json.dumps({"count": len(places), "sample": places[:3]}, ensure_ascii=False, indent=2))
        return

    output = Path(args.output)
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text(json.dumps(places, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    if not args.no_meta:
        meta_path = output.with_suffix(output.suffix + ".meta.json")
        metadata = {
            "providerId": "kakaoLocal",
            "providerName": "카카오 로컬 API 캐시",
            "generatedAt": datetime.now(timezone(timedelta(hours=9))).isoformat(timespec="seconds"),
            "status": "ok",
            "count": len(places),
        }
        meta_path.write_text(json.dumps(metadata, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(f"Wrote {len(places)} places to {output}")


if __name__ == "__main__":
    main()

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
DEFAULT_OUTPUT = ROOT_DIR / "backend/src/main/resources/data/places.json"
KAKAO_KEYWORD_URL = "https://dapi.kakao.com/v2/local/search/keyword.json"
KAKAO_MAX_RADIUS_METERS = 20000

TARGETS = [
    {
        "area": "서울",
        "latitude": 37.5665,
        "longitude": 126.9780,
        "radius": "30000",
        "keywords": ["카페", "브런치 카페", "북카페", "스터디카페", "애견카페", "베이커리 카페"],
    },
    {
        "area": "부산",
        "latitude": 35.1796,
        "longitude": 129.0756,
        "radius": "30000",
        "keywords": ["카페", "브런치", "북카페", "디저트", "반려동물 카페"],
    },
    {
        "area": "인천",
        "latitude": 37.4563,
        "longitude": 126.7052,
        "radius": "25000",
        "keywords": ["카페", "브런치 카페", "베이커리", "키즈 카페", "데이트 카페"],
    },
    {
        "area": "대구",
        "latitude": 35.8714,
        "longitude": 128.6017,
        "radius": "25000",
        "keywords": ["카페", "브런치", "레스토랑", "베이커리", "커피숍"],
    },
    {
        "area": "광주",
        "latitude": 35.1595,
        "longitude": 126.8526,
        "radius": "25000",
        "keywords": ["카페", "브런치", "디저트", "키즈 카페", "북카페"],
    },
    {
        "area": "대전",
        "latitude": 36.3504,
        "longitude": 127.3845,
        "radius": "25000",
        "keywords": ["카페", "브런치", "스터디카페", "디저트", "데이트 카페"],
    },
    {
        "area": "울산",
        "latitude": 35.5384,
        "longitude": 129.3114,
        "radius": "20000",
        "keywords": ["카페", "브런치", "베이커리", "식사", "디저트"],
    },
    {
        "area": "세종",
        "latitude": 36.4800,
        "longitude": 127.2890,
        "radius": "22000",
        "keywords": ["카페", "브런치", "북카페", "디저트", "가족 카페"],
    },
    {
        "area": "제주",
        "latitude": 33.4996,
        "longitude": 126.5312,
        "radius": "25000",
        "keywords": ["카페", "브런치", "디저트", "공원형 카페", "펜션"],
    },
]


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
        ("브런치", ["브런치", "데이트", "주말", "커피", "식사"]),
        ("베이커리", ["베이커리", "디저트", "커피", "데이트", "분위기"]),
        ("디저트", ["디저트", "케이크", "커피", "데이트", "분위기"]),
        ("카페", ["카페", "커피", "작업", "분위기", "휴식"]),
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
    if "브런치" in tags or "식사" in tags:
        return f"{area} 인근의 {category}로, 가벼운 식사와 모임에 적합한 장소입니다."
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
    elif "브런치" in tags or "식사" in tags:
        hints.append("브런치, 식사, 가벼운 모임 질의와 연결됩니다.")
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

#!/usr/bin/env python3
"""Collect KorService2 location-based results and convert them to Pero places.json."""

from __future__ import annotations

import argparse
import json
import os
import sys
import time
import urllib.parse
import urllib.request
from collections import Counter
from dataclasses import dataclass, field
from pathlib import Path
from typing import Any
from urllib.error import HTTPError, URLError

SCRIPT_DIR = Path(__file__).resolve().parent
if str(SCRIPT_DIR) not in sys.path:
    sys.path.insert(0, str(SCRIPT_DIR))

from pero_etl_common import (
    DEFAULT_OUTPUT,
    ROOT_DIR,
    compose_address,
    dedupe_tags,
    extract_district_from_address,
    is_valid_address,
    is_valid_coordinate,
    load_env,
    normalize_text,
    place_completeness_score,
    write_places_with_metadata,
)


DEFAULT_ENDPOINT = "https://apis.data.go.kr/B551011/KorService2"
LOCATION_BASED_LIST_PATH = "/locationBasedList2"
PROVIDER_ID = "koreaTour"
PROVIDER_NAME = "한국관광공사 API 동기화 캐시"
MOBILE_OS = "ETC"
MOBILE_APP = "PeroETL"

CONTENT_TYPE_LABELS = {
    12: "관광지",
    14: "문화시설",
    28: "레포츠",
    32: "숙박",
    38: "쇼핑",
    39: "음식점",
}

DEFAULT_TARGETS = [
    {
        "name": "서울",
        "district": "서울",
        "latitude": 37.5665,
        "longitude": 126.9780,
        "radius": 25000,
        "contentTypeIds": [39, 12, 14, 38],
        "themes": ["카페", "숲", "공원", "데이트", "관광"],
    },
    {
        "name": "부산",
        "district": "부산",
        "latitude": 35.1796,
        "longitude": 129.0756,
        "radius": 25000,
        "contentTypeIds": [39, 12, 14, 38],
        "themes": ["카페", "해안", "바다", "식사", "산책"],
    },
    {
        "name": "인천",
        "district": "인천",
        "latitude": 37.4563,
        "longitude": 126.7052,
        "radius": 25000,
        "contentTypeIds": [39, 12, 14, 38],
        "themes": ["항구", "식사", "카페", "공원", "산책"],
    },
    {
        "name": "대구",
        "district": "대구",
        "latitude": 35.8714,
        "longitude": 128.6017,
        "radius": 25000,
        "contentTypeIds": [39, 12, 14, 38],
        "themes": ["카페", "전시", "도보", "식사", "문화"],
    },
    {
        "name": "대전",
        "district": "대전",
        "latitude": 36.3504,
        "longitude": 127.3845,
        "radius": 24000,
        "contentTypeIds": [39, 12, 14, 38],
        "themes": ["카페", "공원", "문화", "식사", "산책"],
    },
    {
        "name": "광주",
        "district": "광주",
        "latitude": 35.1595,
        "longitude": 126.8526,
        "radius": 24000,
        "contentTypeIds": [39, 12, 14, 38],
        "themes": ["카페", "시장", "식사", "문화", "산책"],
    },
    {
        "name": "울산",
        "district": "울산",
        "latitude": 35.5384,
        "longitude": 129.3114,
        "radius": 24000,
        "contentTypeIds": [39, 12, 14, 38],
        "themes": ["해변", "식사", "카페", "산책", "공원"],
    },
    {
        "name": "세종",
        "district": "세종",
        "latitude": 36.4800,
        "longitude": 127.2890,
        "radius": 22000,
        "contentTypeIds": [39, 12, 14, 38],
        "themes": ["산책", "카페", "식사", "문화", "공원"],
    },
    {
        "name": "경기",
        "district": "경기",
        "latitude": 37.4138,
        "longitude": 127.5183,
        "radius": 30000,
        "contentTypeIds": [39, 12, 14, 38],
        "themes": ["가족", "숲", "카페", "식사", "문화"],
    },
    {
        "name": "강원",
        "district": "강원",
        "latitude": 37.8228,
        "longitude": 128.1555,
        "radius": 30000,
        "contentTypeIds": [39, 12, 14, 38],
        "themes": ["산", "호수", "카페", "식사", "산책"],
    },
    {
        "name": "충북",
        "district": "충북",
        "latitude": 36.6431,
        "longitude": 127.4890,
        "radius": 28000,
        "contentTypeIds": [39, 12, 14, 38],
        "themes": ["전통", "카페", "식사", "산책", "문화"],
    },
    {
        "name": "충남",
        "district": "충남",
        "latitude": 36.5184,
        "longitude": 126.8000,
        "radius": 30000,
        "contentTypeIds": [39, 12, 14, 38],
        "themes": ["해안", "카페", "식사", "산책", "역사"],
    },
    {
        "name": "전북",
        "district": "전북",
        "latitude": 35.8196,
        "longitude": 127.1088,
        "radius": 30000,
        "contentTypeIds": [39, 12, 14, 38],
        "themes": ["전통", "카페", "식사", "숲", "산책"],
    },
    {
        "name": "전남",
        "district": "전남",
        "latitude": 34.8869,
        "longitude": 126.9917,
        "radius": 30000,
        "contentTypeIds": [39, 12, 14, 38],
        "themes": ["해변", "카페", "식사", "산책", "야경"],
    },
    {
        "name": "경북",
        "district": "경북",
        "latitude": 36.4919,
        "longitude": 128.8889,
        "radius": 30000,
        "contentTypeIds": [39, 12, 14, 38],
        "themes": ["산", "카페", "식사", "역사", "산책"],
    },
    {
        "name": "경남",
        "district": "경남",
        "latitude": 35.2270,
        "longitude": 128.6811,
        "radius": 30000,
        "contentTypeIds": [39, 12, 14, 38],
        "themes": ["항구", "카페", "식사", "시장", "산책"],
    },
    {
        "name": "제주",
        "district": "제주",
        "latitude": 33.4996,
        "longitude": 126.5312,
        "radius": 30000,
        "contentTypeIds": [39, 12, 14, 38],
        "themes": ["힐링", "카페", "해안", "식사", "산책"],
    },
]


@dataclass
class CollectStats:
    request_count: int = 0
    api_error_count: int = 0
    parse_error_count: int = 0
    raw_item_count: int = 0
    accepted_count: int = 0
    duplicate_content_id_count: int = 0
    duplicate_signature_count: int = 0
    target_count: int = 0
    failures_by_reason: Counter[str] = field(default_factory=Counter)

    def record_drop(self, reason: str) -> None:
        self.failures_by_reason[reason] += 1

    def to_dict(self) -> dict[str, Any]:
        return {
            "requestCount": self.request_count,
            "apiErrorCount": self.api_error_count,
            "parseErrorCount": self.parse_error_count,
            "rawItemCount": self.raw_item_count,
            "acceptedCount": self.accepted_count,
            "duplicateContentIdCount": self.duplicate_content_id_count,
            "duplicateSignatureCount": self.duplicate_signature_count,
            "targetCount": self.target_count,
            "droppedByReason": dict(sorted(self.failures_by_reason.items())),
        }


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--env", default=str(ROOT_DIR / ".env"), help="Path to .env file")
    parser.add_argument("--output", default=str(DEFAULT_OUTPUT), help="Output places.json path")
    parser.add_argument("--endpoint", default=os.environ.get("KOREA_TOUR_ENDPOINT", DEFAULT_ENDPOINT), help="KorService2 service URL")
    parser.add_argument("--max-places", type=int, default=100, help="Maximum unique places to write")
    parser.add_argument("--num-of-rows", type=int, default=50, help="Rows requested per API page")
    parser.add_argument("--pause", type=float, default=0.15, help="Delay between API calls in seconds")
    parser.add_argument(
        "--regions",
        nargs="*",
        default=[],
        help="Optional target region names. Uses all DEFAULT_TARGETS when omitted.",
    )
    parser.add_argument(
        "--region-target",
        type=int,
        default=0,
        help="Maximum unique places per region. 0 means auto from --max-places.",
    )
    parser.add_argument("--no-meta", action="store_true", help="Skip metadata sidecar generation")
    parser.add_argument("--dry-run", action="store_true", help="Print stats and samples without writing")
    parser.add_argument("--strict", action="store_true", help="Stop on API/network errors instead of continuing")
    return parser.parse_args()


def normalize_service_key(value: str) -> str:
    normalized = normalize_text(value)
    if "%" in normalized:
        return urllib.parse.unquote(normalized)
    return normalized


def request_page(
    endpoint: str,
    service_key: str,
    target: dict[str, Any],
    *,
    content_type_id: int,
    page: int,
    num_of_rows: int,
) -> dict[str, Any]:
    params = {
        "serviceKey": normalize_service_key(service_key),
        "MobileOS": MOBILE_OS,
        "MobileApp": MOBILE_APP,
        "_type": "json",
        "arrange": "E",
        "mapX": str(target["longitude"]),
        "mapY": str(target["latitude"]),
        "radius": str(target["radius"]),
        "contentTypeId": str(content_type_id),
        "numOfRows": str(num_of_rows),
        "pageNo": str(page),
    }
    url = f"{endpoint.rstrip('/')}{LOCATION_BASED_LIST_PATH}?{urllib.parse.urlencode(params)}"
    request = urllib.request.Request(url)
    with urllib.request.urlopen(request, timeout=12) as response:
        return json.loads(response.read().decode("utf-8"))


def response_items(payload: dict[str, Any]) -> tuple[list[dict[str, Any]], int]:
    response = payload.get("response")
    if not isinstance(response, dict):
        raise ValueError("response object is missing")

    header = response.get("header", {})
    if str(header.get("resultCode", "")).strip() not in {"", "0000"}:
        raise ValueError(f"TourAPI error {header.get('resultCode')}: {header.get('resultMsg')}")

    body = response.get("body")
    if not isinstance(body, dict):
        return [], 0

    items = body.get("items")
    raw_items = items.get("item", []) if isinstance(items, dict) else []
    if isinstance(raw_items, dict):
        raw_items = [raw_items]
    if not isinstance(raw_items, list):
        raise ValueError("items.item is not a list")

    total_count = body.get("totalCount", 0)
    try:
        parsed_total_count = int(total_count)
    except (TypeError, ValueError):
        parsed_total_count = 0
    return [item for item in raw_items if isinstance(item, dict)], parsed_total_count


def place_signature(name: str, address: str, latitude: float, longitude: float) -> str:
    normalized_name = normalize_text(name).casefold()
    normalized_address = normalize_text(address).casefold()
    return "|".join(
        [
            normalized_name,
            normalized_address,
            f"{latitude:.4f}",
            f"{longitude:.4f}",
        ]
    )


def derive_category(item: dict[str, Any], content_type_id: int) -> str:
    for key in ("contenttypename", "contentTypeName", "cat3Name", "cat2Name"):
        value = normalize_text(item.get(key))
        if value:
            return value
    return CONTENT_TYPE_LABELS.get(content_type_id, "관광정보")


def build_tags(title: str, category: str, district: str, target: dict[str, Any]) -> list[str]:
    source = f"{title} {category} {' '.join(target.get('themes', []))}"
    tags: list[str] = [district, category]

    rules = [
        ("카페", ["카페", "커피", "휴식", "데이트"]),
        ("공원", ["산책", "야외", "휴식", "데이트"]),
        ("시장", ["시장", "먹거리", "로컬", "쇼핑"]),
        ("박물관", ["전시", "문화", "실내", "관람"]),
        ("미술", ["전시", "문화", "데이트", "관람"]),
        ("쇼핑", ["쇼핑", "편집숍", "데이트", "실내"]),
        ("백화점", ["쇼핑", "실내", "데이트", "가족"]),
        ("식당", ["식사", "맛집", "모임", "데이트"]),
        ("레포츠", ["활동", "체험", "야외", "주말"]),
        ("숙박", ["숙박", "여행", "체류", "예약"]),
    ]

    for needle, candidates in rules:
        if needle in source:
            tags.extend(candidates)

    tags.extend(target.get("themes", []))
    if "서울" in district:
        tags.append("서울")
    return dedupe_tags(tags)


def build_summary(name: str, category: str, district: str, target: dict[str, Any], tags: list[str]) -> str:
    if "산책" in tags:
        return f"{district} 권역의 {category} 유형으로, 산책이나 가벼운 데이트 동선에 맞는 {target['name']} 후보입니다."
    if "쇼핑" in tags:
        return f"{district} 권역의 {category} 유형으로, 쇼핑과 식사 동선을 함께 잡기 쉬운 {target['name']} 후보입니다."
    if "전시" in tags:
        return f"{district} 권역의 {category} 유형으로, 전시·관람 목적 질의와 연결하기 좋은 {target['name']} 후보입니다."
    if "식사" in tags or "맛집" in tags:
        return f"{district} 권역의 {category} 유형으로, 식사와 모임 목적 탐색에 적합한 {target['name']} 후보입니다."
    return f"{district} 권역의 {category} 유형으로, 현재 위치 기반 탐색에 활용할 수 있는 {target['name']} 후보입니다."


def build_search_hints(name: str, category: str, district: str, address: str, target: dict[str, Any], tags: list[str]) -> list[str]:
    hints = [
        f"{name}은(는) KorService2 위치 기반 목록에서 수집한 {category} 데이터입니다.",
        f"{district} · {target['name']} 반경 {target['radius']}m 기준으로 수집했습니다.",
        f"주소 기준 위치는 {address}입니다.",
    ]

    if "데이트" in tags:
        hints.append("데이트, 분위기, 주말 나들이 같은 자연어 질의와 연결됩니다.")
    elif "식사" in tags or "맛집" in tags:
        hints.append("식사, 맛집, 모임, 근처 식당 같은 자연어 질의와 연결됩니다.")
    elif "전시" in tags:
        hints.append("전시, 문화, 실내 관람 같은 자연어 질의와 연결됩니다.")
    else:
        hints.append("근처 갈 만한 곳, 산책, 방문 후보 같은 탐색형 질의와 연결됩니다.")

    return hints


def to_place(item: dict[str, Any], target: dict[str, Any], stats: CollectStats) -> dict[str, Any] | None:
    content_id = normalize_text(item.get("contentid"))
    if not content_id:
        stats.record_drop("missing-contentid")
        return None

    title = normalize_text(item.get("title"))
    if not title:
        stats.record_drop("missing-name")
        return None

    address = normalize_text(item.get("addr1"))
    extra_address = normalize_text(item.get("addr2"))
    full_address = compose_address(address, extra_address)
    if not is_valid_address(full_address):
        stats.record_drop("invalid-address")
        return None

    try:
        latitude = float(item["mapy"])
        longitude = float(item["mapx"])
    except (KeyError, TypeError, ValueError):
        stats.record_drop("invalid-coordinate")
        return None

    if not is_valid_coordinate(latitude, longitude):
        stats.record_drop("out-of-korea-bounds")
        return None

    try:
        content_type_id = int(str(item.get("contenttypeid", "")).strip())
    except ValueError:
        content_type_id = 0

    district = extract_district_from_address(full_address, target["district"])
    category = derive_category(item, content_type_id)
    tags = build_tags(title, category, district, target)
    summary = build_summary(title, category, district, target, tags)
    search_hints = build_search_hints(title, category, district, full_address, target, tags)

    return {
        "id": f"koreaTour-{content_id}",
        "name": title,
        "category": category,
        "district": district,
        "address": full_address,
        "roadAddress": full_address,
        "latitude": latitude,
        "longitude": longitude,
        "summary": summary,
        "tags": tags,
        "searchHints": search_hints,
    }


def should_replace(existing: dict[str, Any], candidate: dict[str, Any]) -> bool:
    return place_completeness_score(candidate) > place_completeness_score(existing)


def status_from_stats(stats: CollectStats, count: int) -> str:
    if count == 0 and (stats.api_error_count or stats.parse_error_count):
        return "empty-partial"
    if count == 0:
        return "empty"
    if stats.api_error_count or stats.parse_error_count:
        return "partial"
    return "ok"


def collect(
    service_key: str,
    *,
    endpoint: str,
    max_places: int,
    num_of_rows: int,
    pause_seconds: float,
    strict: bool,
    region_names: list[str] | None = None,
    region_target: int = 0,
) -> tuple[list[dict[str, Any]], CollectStats]:
    targets = DEFAULT_TARGETS if not region_names else [
        target for target in DEFAULT_TARGETS if target["name"] in region_names
    ]
    if not targets:
        raise ValueError("No matching targets found for --regions.")

    stats = CollectStats(target_count=len(targets))
    if max_places < len(targets):
        region_target = max(1, max_places)
    elif region_target <= 0:
        region_target = max(1, max_places // len(targets))
    else:
        region_target = min(max_places, region_target)

    places_by_id: dict[str, dict[str, Any]] = {}
    signatures: dict[str, str] = {}

    for target in targets:
        per_region_count = 0
        for content_type_id in target["contentTypeIds"]:
            page = 1
            while len(places_by_id) < max_places and per_region_count < region_target:
                stats.request_count += 1
                try:
                    payload = request_page(
                        endpoint,
                        service_key,
                        target,
                        content_type_id=content_type_id,
                        page=page,
                        num_of_rows=num_of_rows,
                    )
                    items, total_count = response_items(payload)
                except (HTTPError, URLError, TimeoutError, ValueError, json.JSONDecodeError) as error:
                    if isinstance(error, ValueError):
                        stats.parse_error_count += 1
                    else:
                        stats.api_error_count += 1
                    if strict:
                        raise
                    break

                if not items:
                    break

                stats.raw_item_count += len(items)
                for item in items:
                    place = to_place(item, target, stats)
                    if place is None:
                        continue

                    existing = places_by_id.get(place["id"])
                    if existing is not None:
                        stats.duplicate_content_id_count += 1
                        if should_replace(existing, place):
                            places_by_id[place["id"]] = place
                        continue

                    signature = place_signature(
                        place["name"],
                        place["address"],
                        place["latitude"],
                        place["longitude"],
                    )
                    if signature in signatures:
                        stats.duplicate_signature_count += 1
                        continue

                    places_by_id[place["id"]] = place
                    signatures[signature] = place["id"]
                    stats.accepted_count += 1
                    per_region_count += 1
                    if len(places_by_id) >= max_places:
                        break
                    if per_region_count >= region_target:
                        break

                if len(places_by_id) >= max_places:
                    break

                if page * num_of_rows >= total_count:
                    break

                page += 1
                time.sleep(pause_seconds)

            time.sleep(pause_seconds)
            if len(places_by_id) >= max_places:
                break

        if len(places_by_id) >= max_places:
            break

    ordered = sorted(
        places_by_id.values(),
        key=lambda place: (place["district"], place["category"], place["name"]),
    )
    return ordered, stats


def main() -> None:
    args = parse_args()
    if args.max_places < 1:
        raise SystemExit("--max-places must be greater than 0.")
    if args.num_of_rows < 1:
        raise SystemExit("--num-of-rows must be greater than 0.")

    load_env(Path(args.env))
    service_key = os.environ.get("KOREA_TOUR_API_SERVICE_KEY") or os.environ.get("KOREA_TOUR_API_KEY")
    if not service_key:
        raise SystemExit("KOREA_TOUR_API_SERVICE_KEY is missing. Add it to .env.")
    endpoint = os.environ.get("KOREA_TOUR_ENDPOINT", args.endpoint)

    places, stats = collect(
        service_key,
        endpoint=endpoint,
        max_places=args.max_places,
        num_of_rows=args.num_of_rows,
        pause_seconds=args.pause,
        strict=args.strict,
        region_names=args.regions,
        region_target=args.region_target,
    )
    status = status_from_stats(stats, len(places))

    if args.dry_run:
        print(
            json.dumps(
                {
                    "providerId": PROVIDER_ID,
                    "providerName": PROVIDER_NAME,
                    "status": status,
                    "count": len(places),
                    "stats": stats.to_dict(),
                    "sample": places[:3],
                },
                ensure_ascii=False,
                indent=2,
            )
        )
        return

    output = Path(args.output)
    meta_path = write_places_with_metadata(
        output,
        places,
        provider_id=PROVIDER_ID,
        provider_name=PROVIDER_NAME,
        status=status,
        no_meta=args.no_meta,
    )
    if meta_path is None:
        print(f"Wrote {len(places)} places to {output} (without metadata sidecar)")
    else:
        print(f"Wrote {len(places)} places to {output} and {meta_path}")
    print(json.dumps({"status": status, "stats": stats.to_dict()}, ensure_ascii=False, indent=2))


if __name__ == "__main__":
    main()

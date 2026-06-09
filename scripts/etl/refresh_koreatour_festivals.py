#!/usr/bin/env python3
"""Refresh KoreaTour festival entries from searchFestival2 into the local Pero cache.

ETL-only: calls KoreaTour while regenerating backend/src/main/resources/data/places.json.
The app/backend request path still reads cached JSON only.
"""

from __future__ import annotations

import argparse
import json
import os
import re
import sys
import time
import urllib.parse
from datetime import date, datetime
from pathlib import Path
from typing import Any
from urllib.error import HTTPError, URLError

SCRIPT_DIR = Path(__file__).resolve().parent
if str(SCRIPT_DIR) not in sys.path:
    sys.path.insert(0, str(SCRIPT_DIR))

from korservice2_to_pero import (  # noqa: E402
    DEFAULT_ENDPOINT,
    PROVIDER_ID,
    CollectStats,
    build_search_hints,
    build_summary,
    build_tags,
    build_theme_tags,
    normalize_service_key,
    request_json,
    response_items,
    to_place,
)
from pero_etl_common import compose_address, extract_district_from_address, is_valid_address, is_valid_coordinate
from pero_etl_common import DEFAULT_OUTPUT, current_timestamp, load_env, normalize_text  # noqa: E402

SEARCH_FESTIVAL_PATH = "/searchFestival2"
TOUR_DATE_FORMAT = "%Y%m%d"
YEAR_PATTERN = re.compile(r"(?<!\d)(20\d{2})(?!\d)")


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--env", default=str(Path(__file__).resolve().parents[2] / ".env"))
    parser.add_argument("--input", default=str(DEFAULT_OUTPUT))
    parser.add_argument("--output", default=str(DEFAULT_OUTPUT))
    parser.add_argument("--endpoint", default=os.environ.get("KOREA_TOUR_ENDPOINT", DEFAULT_ENDPOINT))
    parser.add_argument("--event-start-date", default=date.today().strftime(TOUR_DATE_FORMAT), help="YYYYMMDD lower bound")
    parser.add_argument("--num-of-rows", type=int, default=100)
    parser.add_argument("--pause", type=float, default=0.03)
    parser.add_argument("--max-items", type=int, default=0, help="0 means all searchFestival2 items")
    parser.add_argument("--fast", action="store_true", help="Use searchFestival2 list fields only; skip slow detail calls")
    parser.add_argument("--strict", action="store_true")
    parser.add_argument("--dry-run", action="store_true")
    return parser.parse_args()


def parse_tour_date(value: str | None) -> date | None:
    value = normalize_text(value)
    if not value:
        return None
    try:
        return datetime.strptime(value, TOUR_DATE_FORMAT).date()
    except ValueError:
        return None


def stale_title_year(title: str, current_year: int) -> bool:
    years = [int(match.group(1)) for match in YEAR_PATTERN.finditer(title or "")]
    return any(year < current_year for year in years)


def is_festival_place(place: dict[str, Any]) -> bool:
    tour_api = place.get("tourApi") or {}
    haystack = " ".join(
        [
            normalize_text(place.get("category")),
            normalize_text(place.get("name")),
            " ".join(place.get("tags") or []),
            " ".join(place.get("themeTags") or []),
            normalize_text(tour_api.get("contentTypeId")),
        ]
    )
    return normalize_text(place.get("sourceAttribution")) == PROVIDER_ID and (
        normalize_text(tour_api.get("contentTypeId")) == "15"
        or "행사" in haystack
        or "축제" in haystack
        or "공연" in haystack
    )


def common_dates(place: dict[str, Any]) -> tuple[date | None, date | None]:
    common = ((place.get("tourApi") or {}).get("common") or {})
    return parse_tour_date(common.get("eventStartDate")), parse_tour_date(common.get("eventEndDate"))


def should_drop_existing_festival(place: dict[str, Any], today: date) -> bool:
    if not is_festival_place(place):
        return False
    _, end = common_dates(place)
    return end is None or end < today or stale_title_year(normalize_text(place.get("name")), today.year)


def request_search_festival_page(endpoint: str, service_key: str, *, event_start_date: str, page: int, num_of_rows: int) -> tuple[list[dict[str, Any]], int]:
    params = {
        "serviceKey": normalize_service_key(service_key),
        "MobileOS": "ETC",
        "MobileApp": "PeroETL",
        "_type": "json",
        "eventStartDate": event_start_date,
        "arrange": "A",
        "numOfRows": str(num_of_rows),
        "pageNo": str(page),
    }
    return response_items(request_json(endpoint, SEARCH_FESTIVAL_PATH, params))


def fetch_festival_items(endpoint: str, service_key: str, event_start_date: str, num_of_rows: int, pause: float, max_items: int, strict: bool) -> tuple[list[dict[str, Any]], CollectStats]:
    page = 1
    items: list[dict[str, Any]] = []
    stats = CollectStats()
    while True:
        stats.request_count += 1
        try:
            page_items, total = request_search_festival_page(
                endpoint,
                service_key,
                event_start_date=event_start_date,
                page=page,
                num_of_rows=num_of_rows,
            )
        except (RuntimeError, HTTPError, URLError, TimeoutError, OSError, ValueError, json.JSONDecodeError) as error:
            if strict:
                raise
            stats.api_error_count += 1
            stats.record_drop(f"searchFestival:{normalize_text(str(error)) or type(error).__name__}")
            break
        if not page_items:
            break
        stats.raw_item_count += len(page_items)
        items.extend(page_items)
        if max_items and len(items) >= max_items:
            items = items[:max_items]
            break
        if page * num_of_rows >= total:
            break
        page += 1
        if pause > 0:
            time.sleep(pause)
    return items, stats



def fast_to_place(item: dict[str, Any], stats: CollectStats) -> dict[str, Any] | None:
    content_id = normalize_text(item.get("contentid"))
    title = normalize_text(item.get("title"))
    if not content_id or not title:
        stats.record_drop("missing-contentid-or-title")
        return None
    address = compose_address(normalize_text(item.get("addr1")), normalize_text(item.get("addr2")))
    if not is_valid_address(address):
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
    district = extract_district_from_address(address, normalize_text(item.get("areacode")) or "미상")
    category = "행사/공연/축제"
    common = {
        "tel": normalize_text(item.get("tel")),
        "eventStartDate": normalize_text(item.get("eventstartdate")),
        "eventEndDate": normalize_text(item.get("eventenddate")),
    }
    common = {key: value for key, value in common.items() if value}
    tour_api = {
        "contentId": content_id,
        "contentTypeId": "15",
        "contentTypeLabel": category,
        "common": common,
        "intro": {},
        "images": [],
        "pet": None,
    }
    tags = build_tags(title, category, district, common)
    theme_tags = build_theme_tags(title, category, district, common, None)
    summary = build_summary(title, category, district, theme_tags, None)
    search_hints = build_search_hints(title, category, district, address, theme_tags, common, None)
    stats.accepted_count += 1
    return {
        "id": f"koreaTour-{content_id}",
        "name": title,
        "category": category,
        "district": district,
        "address": address,
        "roadAddress": address,
        "latitude": latitude,
        "longitude": longitude,
        "summary": summary,
        "tags": tags,
        "themeTags": theme_tags,
        "searchHints": search_hints,
        "sourceAttribution": PROVIDER_ID,
        "tourApi": tour_api,
    }

def dedupe_places(places: list[dict[str, Any]]) -> list[dict[str, Any]]:
    by_id: dict[str, dict[str, Any]] = {}
    seen_signatures: set[str] = set()
    output: list[dict[str, Any]] = []
    for place in places:
        place_id = normalize_text(place.get("id"))
        if place_id in by_id:
            continue
        signature = "|".join(
            [
                normalize_text(place.get("name")).casefold(),
                normalize_text(place.get("address")).casefold(),
                f"{float(place.get('latitude', 0)):.4f}",
                f"{float(place.get('longitude', 0)):.4f}",
            ]
        )
        if signature in seen_signatures:
            continue
        by_id[place_id] = place
        seen_signatures.add(signature)
        output.append(place)
    return output


def main() -> int:
    args = parse_args()
    load_env(Path(args.env))
    service_key = os.environ.get("KOREA_TOUR_API_SERVICE_KEY") or os.environ.get("KOREA_TOUR_API_KEY")
    if not service_key:
        print("KOREA_TOUR_API_SERVICE_KEY is missing", file=sys.stderr)
        return 2

    today = parse_tour_date(args.event_start_date) or date.today()
    current_year = today.year
    endpoint = os.environ.get("KOREA_TOUR_ENDPOINT", args.endpoint)
    input_path = Path(args.input)
    output_path = Path(args.output)
    existing: list[dict[str, Any]] = json.loads(input_path.read_text(encoding="utf-8"))

    raw_items, fetch_stats = fetch_festival_items(
        endpoint,
        service_key,
        args.event_start_date,
        args.num_of_rows,
        args.pause,
        args.max_items,
        args.strict,
    )

    convert_stats = CollectStats()
    refreshed: list[dict[str, Any]] = []
    stale_title_count = 0
    expired_count = 0
    for raw in raw_items:
        title = normalize_text(raw.get("title"))
        if stale_title_year(title, current_year):
            stale_title_count += 1
            continue
        end = parse_tour_date(raw.get("eventenddate"))
        if end is not None and end < today:
            expired_count += 1
            continue
        place = fast_to_place(raw, convert_stats) if args.fast else to_place(raw, convert_stats, endpoint=endpoint, service_key=service_key, strict=args.strict)
        if place is None:
            continue
        common = ((place.get("tourApi") or {}).get("common") or {})
        # Keep searchFestival2 period authoritative when detailIntro is stale/missing.
        if normalize_text(raw.get("eventstartdate")):
            common["eventStartDate"] = normalize_text(raw.get("eventstartdate"))
        if normalize_text(raw.get("eventenddate")):
            common["eventEndDate"] = normalize_text(raw.get("eventenddate"))
        place["tourApi"]["common"] = common
        refreshed.append(place)

    kept_existing = [place for place in existing if not should_drop_existing_festival(place, today)]
    merged = dedupe_places(kept_existing + refreshed)
    merged.sort(key=lambda place: (normalize_text(place.get("district")), normalize_text(place.get("category")), normalize_text(place.get("name"))))

    stats = {
        "rawFestivalItems": len(raw_items),
        "refreshedFestivalPlaces": len(refreshed),
        "droppedStaleTitleYear": stale_title_count,
        "droppedExpired": expired_count,
        "droppedExistingFestival": len(existing) - len(kept_existing),
        "beforeCount": len(existing),
        "afterCount": len(merged),
        "fetchStats": fetch_stats.to_dict(),
        "convertStats": convert_stats.to_dict(),
    }
    print(json.dumps(stats, ensure_ascii=False, indent=2))

    if args.dry_run:
        return 0

    output_path.write_text(json.dumps(merged, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    meta_path = output_path.with_suffix(output_path.suffix + ".meta.json")
    meta: dict[str, Any] = {}
    if meta_path.exists():
        try:
            meta = json.loads(meta_path.read_text(encoding="utf-8"))
        except json.JSONDecodeError:
            meta = {}
    meta.update(
        {
            "generatedAt": current_timestamp(),
            "status": "ok" if not fetch_stats.api_error_count else "partial",
            "festivalSearchRefreshedAt": current_timestamp(),
            "festivalSearchEventStartDate": args.event_start_date,
            "festivalSearchRawCount": len(raw_items),
            "festivalSearchAcceptedCount": len(refreshed),
            "festivalSearchDroppedStaleTitleYear": stale_title_count,
        }
    )
    meta_path.write_text(json.dumps(meta, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

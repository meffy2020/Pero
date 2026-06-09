#!/usr/bin/env python3
"""Enrich existing KoreaTour festival cache entries with official period/homepage detail data.

This is an ETL-only script. It calls KorService2 while building the local cache; the app/backend
request path still reads cached JSON only.
"""

from __future__ import annotations

import argparse
import json
import os
import sys
import time
from pathlib import Path
from typing import Any
from urllib.error import HTTPError, URLError

SCRIPT_DIR = Path(__file__).resolve().parent
if str(SCRIPT_DIR) not in sys.path:
    sys.path.insert(0, str(SCRIPT_DIR))

from korservice2_to_pero import (  # noqa: E402
    DEFAULT_ENDPOINT,
    DETAIL_COMMON_PATH,
    DETAIL_INTRO_PATH,
    normalize_service_key,
    request_detail,
    response_items,
    normalize_tour_common,
)
from pero_etl_common import DEFAULT_OUTPUT, current_timestamp, load_env, normalize_text  # noqa: E402


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--env", default=".env", help="Path to .env file")
    parser.add_argument("--input", default=str(DEFAULT_OUTPUT), help="Existing places JSON")
    parser.add_argument("--output", default=str(DEFAULT_OUTPUT), help="Output places JSON")
    parser.add_argument("--endpoint", default=os.environ.get("KOREA_TOUR_ENDPOINT", DEFAULT_ENDPOINT))
    parser.add_argument("--max-places", type=int, default=0, help="Limit enriched festival entries; 0 means all")
    parser.add_argument("--pause", type=float, default=0.04, help="Delay between API calls")
    parser.add_argument("--dry-run", action="store_true")
    return parser.parse_args()


def is_korea_tour_festival(place: dict[str, Any]) -> bool:
    tour_api = place.get("tourApi") or {}
    content_type_id = normalize_text(tour_api.get("contentTypeId"))
    category = normalize_text(place.get("category"))
    tags = " ".join(place.get("tags") or []) + " " + " ".join(place.get("themeTags") or [])
    return normalize_text(place.get("sourceAttribution")) == "koreaTour" and (
        content_type_id == "15" or "행사" in category or "축제" in category or "축제행사" in tags
    )


def has_period_or_homepage(place: dict[str, Any]) -> bool:
    common = ((place.get("tourApi") or {}).get("common") or {})
    return bool(common.get("eventStartDate") or common.get("eventEndDate") or common.get("homepage"))


def fetch_common(endpoint: str, service_key: str, content_id: str, content_type_id: str, pause: float) -> dict[str, str] | None:
    common_item: dict[str, Any] | None = None
    intro_item: dict[str, Any] | None = None
    for path, request_content_type_id in ((DETAIL_COMMON_PATH, None), (DETAIL_INTRO_PATH, content_type_id)):
        try:
            payload = request_detail(
                endpoint,
                normalize_service_key(service_key),
                path,
                content_id=content_id,
                content_type_id=request_content_type_id,
            )
            items, _ = response_items(payload)
        except (RuntimeError, HTTPError, URLError, TimeoutError, OSError, ValueError, json.JSONDecodeError):
            items = []
        if path == DETAIL_COMMON_PATH:
            common_item = items[0] if items else None
        else:
            intro_item = items[0] if items else None
        if pause > 0:
            time.sleep(pause)
    return normalize_tour_common(common_item, intro_item)


def merge_common(existing: dict[str, Any] | None, fetched: dict[str, str] | None) -> dict[str, Any] | None:
    merged: dict[str, Any] = dict(existing or {})
    for key, value in (fetched or {}).items():
        if value and not normalize_text(merged.get(key)):
            merged[key] = value
    return merged or None


def main() -> int:
    args = parse_args()
    load_env(Path(args.env))
    service_key = os.environ.get("KOREA_TOUR_API_SERVICE_KEY") or os.environ.get("KOREA_TOUR_SERVICE_KEY")
    if not service_key:
        print("KOREA_TOUR_API_SERVICE_KEY is missing", file=sys.stderr)
        return 2

    input_path = Path(args.input)
    output_path = Path(args.output)
    places: list[dict[str, Any]] = json.loads(input_path.read_text(encoding="utf-8"))
    candidates = [place for place in places if is_korea_tour_festival(place) and not has_period_or_homepage(place)]
    if args.max_places > 0:
        candidates = candidates[: args.max_places]

    enriched = 0
    with_period = 0
    with_homepage = 0
    for index, place in enumerate(candidates, 1):
        tour_api = place.get("tourApi") or {}
        content_id = normalize_text(tour_api.get("contentId")) or normalize_text(place.get("id", "").replace("koreaTour-", ""))
        content_type_id = normalize_text(tour_api.get("contentTypeId")) or "15"
        if not content_id:
            continue
        fetched = fetch_common(args.endpoint, service_key, content_id, content_type_id, args.pause)
        if not fetched:
            continue
        tour_api["common"] = merge_common(tour_api.get("common"), fetched)
        place["tourApi"] = tour_api
        enriched += 1
        common = tour_api.get("common") or {}
        if common.get("eventStartDate") or common.get("eventEndDate"):
            with_period += 1
        if common.get("homepage"):
            with_homepage += 1
        if index % 50 == 0:
            print(f"processed={index} enriched={enriched} period={with_period} homepage={with_homepage}", file=sys.stderr)

    print(json.dumps({"candidates": len(candidates), "enriched": enriched, "withPeriod": with_period, "withHomepage": with_homepage}, ensure_ascii=False))
    if args.dry_run:
        return 0

    output_path.write_text(json.dumps(places, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    meta_path = output_path.with_suffix(output_path.suffix + ".meta.json")
    if meta_path.exists():
        try:
            meta = json.loads(meta_path.read_text(encoding="utf-8"))
        except json.JSONDecodeError:
            meta = {}
        meta["generatedAt"] = current_timestamp()
        meta["status"] = "ok"
        meta["festivalDetailEnrichedAt"] = current_timestamp()
        meta["festivalDetailEnrichedCount"] = enriched
        meta_path.write_text(json.dumps(meta, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

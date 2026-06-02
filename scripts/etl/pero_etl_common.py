#!/usr/bin/env python3
"""Shared helpers for Pero ETL scripts."""

from __future__ import annotations

import json
import os
from datetime import datetime, timedelta, timezone
from pathlib import Path
from typing import Any


ROOT_DIR = Path(__file__).resolve().parents[2]
DEFAULT_OUTPUT = ROOT_DIR / "backend/src/main/resources/data/places.json"
DEFAULT_SMART_OUTPUT = ROOT_DIR / "backend/src/main/resources/data/places.smartseoul.json"
KST = timezone(timedelta(hours=9))

_REGION_SHORT_NAMES = {
    "서울특별시": "서울",
    "부산광역시": "부산",
    "대구광역시": "대구",
    "인천광역시": "인천",
    "광주광역시": "광주",
    "대전광역시": "대전",
    "울산광역시": "울산",
    "세종특별자치시": "세종",
    "경기도": "경기",
    "강원특별자치도": "강원",
    "강원도": "강원",
    "충청북도": "충북",
    "충청남도": "충남",
    "전북특별자치도": "전북",
    "전라북도": "전북",
    "전라남도": "전남",
    "경상북도": "경북",
    "경상남도": "경남",
    "제주특별자치도": "제주",
}


def load_env(path: Path) -> None:
    if not path.exists():
        return

    for raw_line in path.read_text(encoding="utf-8").splitlines():
        line = raw_line.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        key, value = line.split("=", 1)
        os.environ.setdefault(key.strip(), value.strip().strip('"').strip("'"))


def normalize_text(value: Any) -> str:
    if value is None:
        return ""
    return " ".join(str(value).split())


def compose_address(primary: str, secondary: str) -> str:
    first = normalize_text(primary)
    second = normalize_text(secondary)
    if not first:
        return second
    if not second or second == first:
        return first
    return f"{first} {second}"


def is_valid_coordinate(latitude: float, longitude: float) -> bool:
    return 32.0 <= latitude <= 39.5 and 123.0 <= longitude <= 132.5


def is_valid_address(address: str) -> bool:
    normalized = normalize_text(address)
    if len(normalized) < 5:
        return False
    return any(token in normalized for token in ("시", "도", "구", "군", "읍", "면", "동", "로", "길"))


def extract_district_from_address(address: str, fallback: str) -> str:
    tokens = normalize_text(address).split()
    if len(tokens) >= 2:
        region = _REGION_SHORT_NAMES.get(tokens[0], tokens[0])
        if tokens[1].endswith(("구", "군", "시")):
            return f"{region} {tokens[1]}"
        return region
    return fallback


def dedupe_tags(tags: list[str], limit: int = 6) -> list[str]:
    deduped: list[str] = []
    for tag in tags:
        normalized = normalize_text(tag)
        if normalized and normalized not in deduped:
            deduped.append(normalized)
        if len(deduped) >= limit:
            break
    return deduped


def current_timestamp() -> str:
    return datetime.now(KST).isoformat(timespec="seconds")


def place_completeness_score(place: dict[str, Any]) -> int:
    scalar_fields = (
        "name",
        "category",
        "district",
        "address",
        "roadAddress",
        "summary",
        "sourceAttribution",
    )
    score = sum(1 for field in scalar_fields if normalize_text(place.get(field)))
    score += len(place.get("tags", []))
    score += len(place.get("themeTags", []))
    score += len(place.get("searchHints", []))
    tour_api = place.get("tourApi") or {}
    common = tour_api.get("common") or {}
    images = tour_api.get("images") or []
    score += len(common)
    score += len(images)
    return score


def read_generated_at_from_meta(output: Path) -> datetime | None:
    meta_path = output.with_suffix(output.suffix + ".meta.json")
    if not meta_path.exists():
        return None
    try:
        payload = json.loads(meta_path.read_text(encoding="utf-8"))
        generated_at = normalize_text(payload.get("generatedAt"))
        if not generated_at:
            return None
        return datetime.fromisoformat(generated_at)
    except Exception:
        return None


def write_places_with_metadata(
    output: Path,
    places: list[dict[str, Any]],
    *,
    provider_id: str,
    provider_name: str,
    status: str,
    no_meta: bool,
) -> Path | None:
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text(json.dumps(places, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")

    if no_meta:
        return None

    meta_path = output.with_suffix(output.suffix + ".meta.json")
    metadata = {
        "providerId": provider_id,
        "providerName": provider_name,
        "generatedAt": current_timestamp(),
        "status": status,
        "count": len(places),
    }
    meta_path.write_text(json.dumps(metadata, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    return meta_path

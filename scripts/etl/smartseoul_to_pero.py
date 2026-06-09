#!/usr/bin/env python3
"""Collect Smart Seoul theme API data and convert it to Pero places.smartseoul.json."""

from __future__ import annotations

import argparse
import csv
import html
import json
import os
import re
import sys
import urllib.parse
import urllib.request
from collections import Counter
from dataclasses import dataclass, field
from datetime import date, datetime
from pathlib import Path
from typing import Any
from urllib.error import HTTPError, URLError

SCRIPT_DIR = Path(__file__).resolve().parent
if str(SCRIPT_DIR) not in sys.path:
    sys.path.insert(0, str(SCRIPT_DIR))

from pero_etl_common import (
    DEFAULT_SMART_OUTPUT,
    ROOT_DIR,
    compose_address,
    dedupe_tags,
    extract_district_from_address,
    is_valid_address,
    is_valid_coordinate,
    load_env,
    normalize_text,
    place_completeness_score,
    read_generated_at_from_meta,
    write_places_with_metadata,
)


PROVIDER_ID = "smartSeoul"
PROVIDER_NAME = "스마트서울맵 캐시"
DEFAULT_ENDPOINT = "https://map.seoul.go.kr/openapi/v5"
LEGACY_THEME_ENDPOINT_SUFFIX = "/smgis/apps/theme.do"
THEME_TYPE = "2,4,5"
SUMMARY_MAX_LENGTH = 400

FOOD_TITLE_KEYWORDS = {
    "카페",
    "커피",
    "맛집",
    "브런치",
    "디저트",
    "막국수",
    "찜갈비",
    "삼겹살",
    "제빵",
    "베이커리",
    "식당",
    "레스토랑",
    "푸드",
    "국밥",
    "횟집",
    "족발",
}
FOOD_CATEGORY_KEYWORDS = {"음식점", "식당", "레스토랑", "카페", "베이커리", "주점"}
ADDRESS_KEYS = ["COT_ADDR_FULL_NEW", "COT_ADDR_FULL_OLD", "roadAddress", "address", "addr", "JUSO"]
NAME_KEYS = ["COT_CONTS_NAME", "name", "title", "facilityName", "poiName", "placeName"]
CATEGORY_KEYS = ["SUB_CATE_NAME", "THM_THEME_NAME", "category", "categoryName", "type", "themeName"]
SUMMARY_DIRECT_KEYS = ["COT_CONTS_DETAIL", "summary", "overview", "description", "desc", "content"]
SUMMARY_NAME_KEYWORDS = ("소개", "설명", "내용", "개요", "상세", "특징", "정보", "안내", "비고")
EVENT_SCHEDULE_NAME_KEYWORDS = ("일시", "기간", "일정", "행사기간", "축제기간", "운영기간")
USETIME_NAME_KEYWORDS = ("운영시간", "이용시간", "관람시간", "개방시간")
PARKING_NAME_KEYWORDS = ("주차", "주차장")
PET_NAME_KEYWORDS = ("반려", "애견", "동물동반")
EVENT_KEYWORDS = ("축제", "행사", "공연", "페스티벌")
TOURISM_THEME_KEYWORDS = (
    "관광", "축제", "행사", "공연", "문화", "예술", "전시", "박물관", "미술", "역사", "유산", "명소",
    "여행", "나들이", "산책", "공원", "숲", "정원", "둘레길", "한강", "야경", "전망", "무장애", "반려",
)
NON_TOURISM_THEME_KEYWORDS = (
    "공중화장실", "주차장", "민원", "행정", "상수도", "하수도", "복지", "보건", "약국", "병원",
    "파출소", "소방서", "주민센터", "대피소", "도시계획", "CCTV", "기후동행카드", "판매처",
    "학교", "통학", "중개사", "충전기", "편의시설", "출입구", "안전", "안심", "GIS",
    "나눔", "공유", "위탁소", "키움센터", "상담", "레스토랑", "음식점", "부동산",
)
ID_KEYS = ["COT_CONTS_ID", "id", "poiId", "contentId", "sourceId", "OBJECTID", "gid", "pk"]
LAT_KEYS = ["COT_COORD_Y", "latitude", "lat", "y", "coord_y", "mapy", "pointY", "POINT_Y", "Y"]
LNG_KEYS = ["COT_COORD_X", "longitude", "lon", "lng", "x", "coord_x", "mapx", "pointX", "POINT_X", "X"]
TEL_KEYS = ["COT_TEL_NO", "tel", "phone", "contact", "telephone"]
HOMEPAGE_KEYS = ["homepage", "website", "url", "link", "THM_APP_W_LINK"]
USETIME_KEYS = ["useTime", "operationTime", "hours", "openingHours"]
PARKING_KEYS = ["parking", "parkingInfo", "parkingYn"]
PET_KEYS = ["petInfo", "petFriendly", "petYn"]
IMAGE_KEYS = ["COT_IMG_MAIN_URL", "image", "imageUrl", "firstimage", "thumbnail", "thumbUrl"]
MODIFIED_KEYS = ["COT_UPDATE_DATE", "THM_UPDATE_DATE", "modifiedAt", "updatedAt", "lastModified", "regDate", "updateDate"]
YEAR_RE = re.compile(r"20\d{2}")
DATE_TOKEN_RE = re.compile(r"(?:(20\d{2})\s*[.\-/년]\s*)?(\d{1,2})\s*[.\-/월]\s*(\d{1,2})")


class SmartSeoulApiError(RuntimeError):
    pass


@dataclass
class ThemeSeed:
    theme_id: str
    theme_name: str
    theme_detail: str
    theme_type: str
    subcategories: dict[str, str]
    theme_update_date: str


@dataclass(frozen=True)
class EventSchedule:
    raw: str
    start: date
    end: date

    @property
    def start_value(self) -> str:
        return self.start.strftime("%Y%m%d")

    @property
    def end_value(self) -> str:
        return self.end.strftime("%Y%m%d")


@dataclass
class CollectStats:
    source_count: int = 0
    request_count: int = 0
    api_error_count: int = 0
    parse_error_count: int = 0
    raw_item_count: int = 0
    accepted_count: int = 0
    duplicate_content_id_count: int = 0
    duplicate_signature_count: int = 0
    theme_count: int = 0
    failures_by_reason: Counter[str] = field(default_factory=Counter)

    def record_drop(self, reason: str) -> None:
        self.failures_by_reason[reason] += 1

    def to_dict(self) -> dict[str, Any]:
        return {
            "sourceCount": self.source_count,
            "requestCount": self.request_count,
            "apiErrorCount": self.api_error_count,
            "parseErrorCount": self.parse_error_count,
            "rawItemCount": self.raw_item_count,
            "acceptedCount": self.accepted_count,
            "droppedCount": sum(self.failures_by_reason.values()),
            "duplicateContentIdCount": self.duplicate_content_id_count,
            "duplicateSignatureCount": self.duplicate_signature_count,
            "themeCount": self.theme_count,
            "droppedByReason": dict(sorted(self.failures_by_reason.items())),
        }


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--env", default=str(ROOT_DIR / ".env"), help="Path to .env file")
    parser.add_argument("--output", default=str(DEFAULT_SMART_OUTPUT), help="Output places.smartseoul.json path")
    parser.add_argument("--mode", choices=["full", "incremental"], default="full", help="Collection mode")
    parser.add_argument("--endpoint", default=DEFAULT_ENDPOINT, help="Smart Seoul OpenAPI v5 endpoint or legacy theme.do endpoint")
    parser.add_argument("--source-path", default="", help="Optional fallback source file path override")
    parser.add_argument("--source-url", default="", help="Optional fallback source URL override")
    parser.add_argument("--max-places", type=int, default=0, help="Maximum unique places to write. 0 means unlimited")
    parser.add_argument("--no-meta", action="store_true", help="Skip metadata sidecar generation")
    parser.add_argument("--dry-run", action="store_true", help="Print stats and samples without writing")
    parser.add_argument("--strict", action="store_true", help="Stop on source parsing errors instead of continuing")
    return parser.parse_args()


def decode_html_text(value: Any) -> str:
    return normalize_text(html.unescape(str(value))) if value is not None else ""


def get_first(source: dict[str, Any], keys: list[str]) -> str:
    for key in keys:
        value = decode_html_text(source.get(key))
        if value:
            return value
    return ""


def parse_float(value: Any) -> float | None:
    normalized = normalize_text(value)
    if not normalized:
        return None
    try:
        return float(normalized)
    except ValueError:
        return None


def parse_modified_at(raw_item: dict[str, Any]) -> datetime | None:
    raw_value = get_first(raw_item, MODIFIED_KEYS)
    if not raw_value:
        return None
    normalized = raw_value.replace(".", "-").replace("/", "-").strip()
    if normalized.endswith("Z"):
        normalized = normalized[:-1] + "+00:00"
    for parser in (
        lambda value: datetime.fromisoformat(value),
        lambda value: datetime.strptime(value, "%Y-%m-%d %H:%M:%S"),
        lambda value: datetime.strptime(value, "%Y-%m-%d"),
        lambda value: datetime.strptime(value, "%Y%m%d%H%M%S"),
        lambda value: datetime.strptime(value, "%Y%m%d"),
    ):
        try:
            return parser(normalized)
        except ValueError:
            continue
    return None


def parse_source_payload(text: str) -> list[dict[str, Any]]:
    try:
        payload = json.loads(text)
        if isinstance(payload, list):
            return [item for item in payload if isinstance(item, dict)]
        if isinstance(payload, dict):
            for key in ("features", "items", "rows", "data", "body"):
                value = payload.get(key)
                if isinstance(value, list):
                    return [item for item in value if isinstance(item, dict)]
        return []
    except json.JSONDecodeError:
        rows = list(csv.DictReader(text.splitlines()))
        return [dict(row) for row in rows]


def uses_legacy_theme_endpoint(endpoint: str) -> bool:
    return endpoint.rstrip("/").endswith(LEGACY_THEME_ENDPOINT_SUFFIX)


def request_legacy_api(endpoint: str, params: dict[str, str], stats: CollectStats) -> dict[str, Any]:
    stats.request_count += 1
    url = f"{endpoint}?{urllib.parse.urlencode(params)}"
    with urllib.request.urlopen(url, timeout=30) as response:
        return json.loads(response.read().decode("utf-8"))


def request_v5_api(endpoint: str, api_key: str, path: str, params: dict[str, str], stats: CollectStats) -> dict[str, Any]:
    stats.request_count += 1
    encoded_key = urllib.parse.quote(api_key, safe="")
    base = endpoint.rstrip("/")
    if "{OpenAPIThemeKey}" in base:
        base = base.replace("{OpenAPIThemeKey}", encoded_key)
    elif "{key}" in base:
        base = base.replace("{key}", encoded_key)
    elif "/openapi/v5/" not in base:
        base = f"{base}/{encoded_key}/public"
    elif not base.endswith("/public"):
        base = f"{base}/public"

    url = f"{base}/{path.lstrip('/')}?{urllib.parse.urlencode(params)}"
    with urllib.request.urlopen(url, timeout=30) as response:
        return json.loads(response.read().decode("utf-8"))


def parse_api_payload(payload: dict[str, Any]) -> tuple[list[dict[str, Any]], dict[str, Any]]:
    head = payload.get("head")
    body = payload.get("body")
    if not isinstance(head, dict) or not isinstance(body, list):
        raise SmartSeoulApiError("invalid-payload")

    retcode = normalize_text(head.get("RETCODE"))
    if retcode == "100":
        return [], head
    if retcode != "0":
        raise SmartSeoulApiError(f"retcode-{retcode or 'unknown'}")

    items = [item for item in body if isinstance(item, dict)]
    return items, head


def fetch_theme_list(endpoint: str, api_key: str, stats: CollectStats) -> list[ThemeSeed]:
    themes: list[ThemeSeed] = []
    page_no = 1
    page_size = 100
    while True:
        if uses_legacy_theme_endpoint(endpoint):
            payload = request_legacy_api(endpoint, {
                "cmd": "themeListNew",
                "key": api_key,
                "theme_type": THEME_TYPE,
                "page_size": str(page_size),
                "page_no": str(page_no),
            }, stats)
        else:
            payload = request_v5_api(endpoint, api_key, "themes/ko", {
                "theme_type": THEME_TYPE,
                "page_size": str(page_size),
                "page_no": str(page_no),
            }, stats)
        items, head = parse_api_payload(payload)
        if not items:
            break
        for item in items:
            if get_first(item, ["THM_THEME_STAT"]) != "1":
                continue
            subcategories = {}
            raw_subcategories = item.get("SUBCATE")
            if isinstance(raw_subcategories, list):
                for sub in raw_subcategories:
                    if not isinstance(sub, dict):
                        continue
                    sub_id = get_first(sub, ["SUB_CATE_ID"])
                    sub_name = get_first(sub, ["SUB_CATE_NAME"])
                    if sub_id and sub_name:
                        subcategories[sub_id] = sub_name
            themes.append(
                ThemeSeed(
                    theme_id=get_first(item, ["THM_THEME_ID"]),
                    theme_name=get_first(item, ["THM_THEME_NAME"]),
                    theme_detail=get_first(item, ["THM_THEME_DETAIL"]),
                    theme_type=get_first(item, ["THM_THEME_TYPE"]),
                    subcategories=subcategories,
                    theme_update_date=get_first(item, ["THM_UPDATE_DATE", "THM_REG_DATE"]),
                )
            )
        total_pages = int(normalize_text(head.get("PAGE_COUNT")) or "1")
        if page_no >= total_pages:
            break
        page_no += 1
    stats.theme_count = len(themes)
    stats.source_count = len(themes)
    return themes


def fetch_theme_contents(endpoint: str, api_key: str, theme: ThemeSeed, stats: CollectStats, strict: bool) -> list[dict[str, Any]]:
    if not uses_legacy_theme_endpoint(endpoint):
        items: list[dict[str, Any]] = []
        page_no = 1
        page_size = 100
        while True:
            try:
                payload = request_v5_api(endpoint, api_key, "themes/contents/ko", {
                    "theme_id": theme.theme_id,
                    "page_size": str(page_size),
                    "page_no": str(page_no),
                    "coord_x": "126.9784",
                    "coord_y": "37.5666",
                    "distance": "200000",
                    "search_type": "0",
                    "search_name": "",
                }, stats)
                page_items, head = parse_api_payload(payload)
            except SmartSeoulApiError as error:
                if strict:
                    raise
                stats.api_error_count += 1
                stats.record_drop(f"theme-{theme.theme_id}:v5:{normalize_text(str(error))}")
                break
            except (HTTPError, URLError, TimeoutError, ValueError, json.JSONDecodeError):
                if strict:
                    raise
                stats.parse_error_count += 1
                stats.record_drop(f"theme-{theme.theme_id}:v5:parse-error")
                break

            if not page_items:
                break
            items.extend(page_items)
            total_pages = int(normalize_text(head.get("PAGE_COUNT")) or "1")
            if page_no >= total_pages:
                break
            page_no += 1
        return items

    try:
        payload = request_legacy_api(endpoint, {
            "cmd": "getContentsListAll",
            "key": api_key,
            "theme_id": theme.theme_id,
        }, stats)
        items, _ = parse_api_payload(payload)
        if items:
            return items
    except SmartSeoulApiError as error:
        if normalize_text(str(error)) != "retcode-0":
            if strict:
                raise
            stats.api_error_count += 1
            stats.record_drop(f"theme-{theme.theme_id}:all:{normalize_text(str(error))}")
    except (HTTPError, URLError, TimeoutError, ValueError, json.JSONDecodeError):
        if strict:
            raise
        stats.parse_error_count += 1
        stats.record_drop(f"theme-{theme.theme_id}:all:parse-error")

    items: list[dict[str, Any]] = []
    if not theme.subcategories:
        return items

    for subcategory_id in theme.subcategories:
        page_no = 1
        page_size = 100
        while True:
            try:
                payload = request_legacy_api(endpoint, {
                    "cmd": "getContentsList",
                    "key": api_key,
                    "theme_id": theme.theme_id,
                    "subcate_id": f"{theme.theme_id},{subcategory_id}",
                    "page_size": str(page_size),
                    "page_no": str(page_no),
                    "coord_x": "126.9784",
                    "coord_y": "37.5666",
                    "distance": "200000",
                    "search_type": "0",
                    "search_name": "",
                }, stats)
                page_items, head = parse_api_payload(payload)
            except SmartSeoulApiError as error:
                if strict:
                    raise
                stats.api_error_count += 1
                stats.record_drop(f"theme-{theme.theme_id}:sub-{subcategory_id}:{normalize_text(str(error))}")
                break
            except (HTTPError, URLError, TimeoutError, ValueError, json.JSONDecodeError):
                if strict:
                    raise
                stats.parse_error_count += 1
                stats.record_drop(f"theme-{theme.theme_id}:sub-{subcategory_id}:parse-error")
                break

            if not page_items:
                break
            items.extend(page_items)
            total_pages = int(normalize_text(head.get("PAGE_COUNT")) or "1")
            if page_no >= total_pages:
                break
            page_no += 1
    return items


def is_food_focused_place(title: str, category: str, overview: str | None) -> bool:
    normalized_title = normalize_text(title)
    normalized_category = normalize_text(category)
    normalized_overview = normalize_text(overview)
    if any(keyword in normalized_title for keyword in FOOD_TITLE_KEYWORDS):
        return True
    if any(keyword in normalized_category for keyword in FOOD_CATEGORY_KEYWORDS):
        return True
    return any(keyword in normalized_overview for keyword in ("맛집", "브런치", "디저트", "카페", "식당", "레스토랑"))


def is_non_tourism_place(name: str, category: str, theme_name: str, summary: str) -> bool:
    haystack = f"{name} {category} {theme_name} {summary}"
    return any(keyword in haystack for keyword in NON_TOURISM_THEME_KEYWORDS)


def is_relevant_theme(theme: ThemeSeed) -> bool:
    haystack = f"{theme.theme_name} {theme.theme_detail}"
    if any(keyword in haystack for keyword in NON_TOURISM_THEME_KEYWORDS):
        return False
    if any(keyword in haystack for keyword in TOURISM_THEME_KEYWORDS):
        return True
    return False


def trim_summary(value: str | None, max_length: int = SUMMARY_MAX_LENGTH) -> str:
    summary = normalize_text(value)
    if len(summary) <= max_length:
        return summary
    return summary[:max_length].rstrip()


def is_probable_description(value: str) -> bool:
    summary = normalize_text(value)
    if len(summary) < 24:
        return False
    if summary.startswith(("http://", "https://")):
        return False
    return any(token in summary for token in (" ", ".", ",", "입니다", "합니다", "제공", "소개", "안내", "운영", "위치", "시설", "체험", "관람"))


def extract_summary_seed(raw_item: dict[str, Any]) -> str:
    direct_summary = get_first(raw_item, SUMMARY_DIRECT_KEYS)
    if direct_summary:
        return direct_summary

    named_candidates: list[str] = []
    fallback_candidates: list[str] = []
    for index in range(1, 21):
        name = get_first(raw_item, [f"COT_NAME_{index:02d}"])
        value = get_first(raw_item, [f"COT_VALUE_{index:02d}"])
        if not value:
            continue
        if name and any(keyword in name for keyword in SUMMARY_NAME_KEYWORDS):
            named_candidates.append(value)
        elif is_probable_description(value):
            fallback_candidates.append(value)

    return next((candidate for candidate in named_candidates if normalize_text(candidate)), "") or next(
        (candidate for candidate in fallback_candidates if normalize_text(candidate)),
        "",
    )


def extract_named_value(raw_item: dict[str, Any], name_keywords: tuple[str, ...]) -> str:
    for index in range(1, 21):
        name = get_first(raw_item, [f"COT_NAME_{index:02d}"])
        value = get_first(raw_item, [f"COT_VALUE_{index:02d}"])
        if name and value and any(keyword in name for keyword in name_keywords):
            return value
    return ""


def infer_event_year(*values: str) -> int:
    for value in values:
        match = YEAR_RE.search(normalize_text(value))
        if match:
            return int(match.group(0))
    return date.today().year


def parse_event_schedule(raw_schedule: str, fallback_year: int) -> EventSchedule | None:
    schedule = normalize_text(raw_schedule)
    if not schedule:
        return None

    dates: list[tuple[date, bool]] = []
    for match in DATE_TOKEN_RE.finditer(schedule):
        explicit_year = bool(match.group(1))
        year = int(match.group(1)) if explicit_year else fallback_year
        month = int(match.group(2))
        day = int(match.group(3))
        try:
            dates.append((date(year, month, day), explicit_year))
        except ValueError:
            continue

    if not dates:
        return None

    start = dates[0][0]
    end, end_has_explicit_year = dates[-1]
    if end < start and not end_has_explicit_year:
        try:
            end = date(end.year + 1, end.month, end.day)
        except ValueError:
            return None

    return EventSchedule(raw=schedule, start=start, end=end)


def extract_event_schedule(raw_item: dict[str, Any], theme: ThemeSeed, name: str, summary: str) -> EventSchedule | None:
    raw_schedule = extract_named_value(raw_item, EVENT_SCHEDULE_NAME_KEYWORDS)
    if not raw_schedule:
        return None
    fallback_year = infer_event_year(name, raw_schedule, theme.theme_name, theme.theme_detail, summary, theme.theme_update_date)
    return parse_event_schedule(raw_schedule, fallback_year)


def is_event_like_place(name: str, category: str, theme_name: str, summary: str) -> bool:
    haystack = f"{name} {category} {theme_name} {summary}"
    return any(keyword in haystack for keyword in EVENT_KEYWORDS)


def is_past_event_schedule(event_schedule: EventSchedule, today: date | None = None) -> bool:
    current_date = today or date.today()
    return event_schedule.end < current_date


def build_tags(name: str, category: str, district: str, theme_name: str, summary: str) -> list[str]:
    haystack = f"{name} {category} {district} {theme_name} {summary}"
    tags = [district, category, "서울", theme_name]
    if any(keyword in haystack for keyword in ("행사", "축제", "공연")):
        tags.extend(["행사", "축제"])
    if any(keyword in haystack for keyword in ("산책", "공원", "숲", "정원", "둘레길", "한강", "전망")):
        tags.extend(["산책", "야외", "휴식"])
    if any(keyword in haystack for keyword in ("전시", "문화", "실내", "관람", "박물관", "미술")):
        tags.extend(["문화", "전시", "실내"])
    if any(keyword in haystack for keyword in ("가족", "아이", "키즈", "체험")):
        tags.extend(["가족", "체험"])
    if any(keyword in haystack for keyword in ("무장애", "배리어프리", "휠체어")):
        tags.append("무장애")
    if any(keyword in haystack for keyword in ("반려", "애견", "펫")):
        tags.append("반려")
    return dedupe_tags(tags, limit=8)


def build_theme_tags(name: str, category: str, theme_name: str, summary: str, pet_info: str) -> list[str]:
    haystack = f"{name} {category} {theme_name} {summary} {pet_info}"
    theme_tags = ["서울"]
    if any(keyword in haystack for keyword in ("행사", "축제", "공연")):
        theme_tags.append("축제행사")
    if any(keyword in haystack for keyword in ("산책", "공원", "숲", "정원", "둘레길", "한강", "전망")):
        theme_tags.append("자연산책")
    if any(keyword in haystack for keyword in ("전시", "문화", "실내", "관람", "박물관", "미술")):
        theme_tags.append("실내데이트")
    if any(keyword in haystack for keyword in ("가족", "아이", "키즈", "체험")):
        theme_tags.append("가족나들이")
    if any(keyword in haystack for keyword in ("반려", "애견", "펫")) or pet_info:
        theme_tags.append("반려동물동반")
    if any(keyword in haystack for keyword in ("무장애", "배리어프리", "휠체어")):
        theme_tags.append("무장애여행")
    return dedupe_tags(theme_tags, limit=8)


def build_summary(theme_name: str, theme_detail: str, district: str, category: str, summary: str, theme_tags: list[str]) -> str:
    normalized_summary = trim_summary(summary)
    if normalized_summary:
        return normalized_summary
    if theme_detail:
        return trim_summary(theme_detail)
    if "축제행사" in theme_tags:
        return f"{district} 권역의 {category} 유형으로, 서울 테마 행사 맥락에 연결하기 좋은 후보입니다."
    if "자연산책" in theme_tags:
        return f"{district} 권역의 {category} 유형으로, 서울 산책 동선과 연결하기 좋은 후보입니다."
    if "실내데이트" in theme_tags:
        return f"{district} 권역의 {category} 유형으로, 서울 문화·전시 흐름에 맞는 후보입니다."
    return f"{district} 권역의 {theme_name} 테마에 속한 서울 탐색 후보입니다."


def build_tour_api_stub(
    source_id: str,
    category: str,
    overview: str,
    tel: str,
    homepage: str,
    use_time: str,
    parking: str,
    pet_info: str,
    image_url: str,
    event_schedule: EventSchedule | None,
) -> dict[str, Any] | None:
    common = {key: value for key, value in {
        "tel": tel,
        "homepage": homepage,
        "overview": overview,
        "useTime": use_time,
        "parking": parking,
        "eventStartDate": event_schedule.start_value if event_schedule else "",
        "eventEndDate": event_schedule.end_value if event_schedule else "",
    }.items() if value}
    intro = {}
    if event_schedule:
        intro = {
            "eventstartdate": event_schedule.start_value,
            "eventenddate": event_schedule.end_value,
            "playtime": event_schedule.raw,
        }
    images = [{"originImgUrl": image_url, "smallImageUrl": image_url, "imgName": "smartseoul", "serialNum": "1"}] if image_url else []
    pet = {"petTursmInfo": pet_info} if pet_info else None
    if not common and not images and not pet:
        return None
    return {
        "contentId": source_id,
        "contentTypeId": None,
        "contentTypeLabel": category,
        "common": common or None,
        "intro": intro,
        "images": images,
        "pet": pet,
    }


def to_absolute_image_url(value: str) -> str:
    normalized = normalize_text(value)
    if not normalized:
        return ""
    if normalized.startswith("http://") or normalized.startswith("https://"):
        return normalized
    if normalized.startswith("/"):
        return f"https://map.seoul.go.kr{normalized}"
    return normalized


def normalize_item(raw_item: dict[str, Any], theme: ThemeSeed, stats: CollectStats) -> dict[str, Any] | None:
    source_id = get_first(raw_item, ID_KEYS)
    if not source_id:
        stats.record_drop("missing-source-id")
        return None

    name = get_first(raw_item, NAME_KEYS)
    if not name:
        stats.record_drop("missing-name")
        return None

    content_status = get_first(raw_item, ["COT_CONTS_STAT"])
    if content_status and content_status != "1":
        stats.record_drop("inactive-content-status")
        return None

    category = get_first(raw_item, CATEGORY_KEYS) or theme.theme_name or "서울 생활지도"
    address = get_first(raw_item, ADDRESS_KEYS)
    full_address = compose_address(address, "")
    if not is_valid_address(full_address):
        stats.record_drop("invalid-address")
        return None

    district = extract_district_from_address(full_address, "서울")
    if "서울" not in district:
        stats.record_drop("non-seoul-place")
        return None

    latitude = next((parsed for key in LAT_KEYS if (parsed := parse_float(raw_item.get(key))) is not None), None)
    longitude = next((parsed for key in LNG_KEYS if (parsed := parse_float(raw_item.get(key))) is not None), None)
    if latitude is None or longitude is None or not is_valid_coordinate(latitude, longitude):
        stats.record_drop("invalid-coordinate")
        return None

    summary_seed = extract_summary_seed(raw_item)
    event_like = is_event_like_place(name, category, theme.theme_name, summary_seed or theme.theme_detail)
    event_schedule = extract_event_schedule(raw_item, theme, name, summary_seed or theme.theme_detail)
    if event_schedule and is_past_event_schedule(event_schedule):
        stats.record_drop("past-event")
        return None
    if event_like and not event_schedule:
        stats.record_drop("event-missing-or-unparseable-schedule")
        return None

    tel = get_first(raw_item, TEL_KEYS)
    homepage = get_first(raw_item, HOMEPAGE_KEYS)
    use_time = extract_named_value(raw_item, USETIME_NAME_KEYWORDS) or get_first(raw_item, USETIME_KEYS) or (event_schedule.raw if event_schedule else "")
    parking = extract_named_value(raw_item, PARKING_NAME_KEYWORDS) or get_first(raw_item, PARKING_KEYS)
    pet_info = extract_named_value(raw_item, PET_NAME_KEYWORDS) or get_first(raw_item, PET_KEYS)
    image_url = to_absolute_image_url(get_first(raw_item, IMAGE_KEYS))

    if is_food_focused_place(name, category, summary_seed):
        stats.record_drop("food-focused-place")
        return None
    if is_non_tourism_place(name, category, theme.theme_name, summary_seed or theme.theme_detail):
        stats.record_drop("non-tourism-place")
        return None

    theme_tags = build_theme_tags(name, category, theme.theme_name, summary_seed or theme.theme_detail, pet_info)
    normalized_summary = build_summary(theme.theme_name, theme.theme_detail, district, category, summary_seed, theme_tags)
    tags = build_tags(name, category, district, theme.theme_name, normalized_summary)
    hints = [
        f"{name}은(는) Smart Seoul API 테마 {theme.theme_name}에서 정규화한 {category} 데이터입니다.",
        f"행정권역은 {district}이며 주소는 {full_address}입니다.",
    ]
    if theme.theme_detail:
        hints.append(f"테마 설명: {theme.theme_detail}")
    if normalized_summary:
        hints.append(f"상세 설명: {normalized_summary}")
    if use_time:
        hints.append(f"운영 시간 정보: {use_time}")
    if parking:
        hints.append(f"주차 정보: {parking}")
    if pet_info:
        hints.append(f"반려동물 정보: {pet_info}")

    return {
        "id": f"smartSeoul-{source_id}",
        "name": name,
        "category": category,
        "district": district,
        "address": full_address,
        "roadAddress": full_address,
        "latitude": latitude,
        "longitude": longitude,
        "summary": normalized_summary,
        "tags": tags,
        "themeTags": theme_tags,
        "searchHints": hints,
        "sourceAttribution": PROVIDER_ID,
        "tourApi": build_tour_api_stub(source_id, category, trim_summary(summary_seed), tel, homepage, use_time, parking, pet_info, image_url, event_schedule),
    }


def place_signature(name: str, address: str, latitude: float, longitude: float) -> str:
    return "|".join([
        normalize_text(name).casefold(),
        normalize_text(address).casefold(),
        f"{latitude:.4f}",
        f"{longitude:.4f}",
    ])


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


def load_fallback_items(source_path: str | None, source_url: str | None, stats: CollectStats) -> list[dict[str, Any]]:
    items: list[dict[str, Any]] = []
    if source_path:
        text = Path(source_path).read_text(encoding="utf-8")
        items.extend(parse_source_payload(text))
        stats.source_count += 1
    if source_url:
        stats.request_count += 1
        with urllib.request.urlopen(source_url, timeout=30) as response:
            items.extend(parse_source_payload(response.read().decode("utf-8")))
        stats.source_count += 1
    return items


def collect(
    *,
    source_path: str | None,
    source_url: str | None,
    mode: str,
    output: str | None,
    max_places: int,
    strict: bool,
    endpoint: str = DEFAULT_ENDPOINT,
    progress: bool = False,
) -> tuple[list[dict[str, Any]], CollectStats]:
    stats = CollectStats()
    limit = max_places if max_places and max_places > 0 else None
    places_by_id: dict[str, dict[str, Any]] = {}
    signatures: dict[str, str] = {}
    incremental_cutoff = read_generated_at_from_meta(Path(output)) if mode == "incremental" and output else None
    incremental_supported = False

    api_key = normalize_text(os.environ.get("SMART_SEOUL_MAP_THEME_API_KEY") or os.environ.get("SMART_SEOUL_MAP_API_KEY"))
    themes: list[ThemeSeed] = []
    items_by_theme: list[tuple[ThemeSeed, dict[str, Any]]] = []

    if api_key:
        try:
            themes = fetch_theme_list(endpoint, api_key, stats)
            relevant_count = sum(1 for theme in themes if is_relevant_theme(theme))
            if progress:
                print(f"[smartseoul][themes] total={len(themes)} relevant={relevant_count}", file=sys.stderr, flush=True)
            relevant_index = 0
            for theme in themes:
                if not is_relevant_theme(theme):
                    stats.record_drop("irrelevant-theme")
                    continue
                relevant_index += 1
                if progress:
                    print(f"[smartseoul][theme] {relevant_index}/{relevant_count} {theme.theme_name}", file=sys.stderr, flush=True)
                theme_items = fetch_theme_contents(endpoint, api_key, theme, stats, strict)
                if progress:
                    print(f"[smartseoul][theme] {theme.theme_name} fetched={len(theme_items)}", file=sys.stderr, flush=True)
                for item in theme_items:
                    items_by_theme.append((theme, item))
        except SmartSeoulApiError as error:
            if strict:
                raise
            stats.api_error_count += 1
            stats.record_drop(f"auth/permission:{normalize_text(str(error))}")
        except (HTTPError, URLError, TimeoutError, ValueError, json.JSONDecodeError):
            if strict:
                raise
            stats.parse_error_count += 1
            stats.record_drop("api-shape/parse")

    if not items_by_theme and (source_path or source_url):
        try:
            fallback_items = load_fallback_items(source_path, source_url, stats)
            fallback_theme = ThemeSeed(theme_id="fallback", theme_name="Smart Seoul fallback", theme_detail="", theme_type="2", subcategories={}, theme_update_date="")
            items_by_theme = [(fallback_theme, item) for item in fallback_items]
        except (FileNotFoundError, HTTPError, URLError, OSError, json.JSONDecodeError, csv.Error):
            if strict:
                raise
            stats.parse_error_count += 1
            stats.record_drop("fallback-source-error")

    stats.raw_item_count = len(items_by_theme)
    for theme, raw_item in items_by_theme:
        if incremental_cutoff is not None:
            modified_at = parse_modified_at(raw_item) or parse_modified_at({"THM_UPDATE_DATE": theme.theme_update_date})
            if modified_at is not None:
                incremental_supported = True
                cutoff = incremental_cutoff.replace(tzinfo=None) if incremental_cutoff.tzinfo else incremental_cutoff
                if modified_at <= cutoff:
                    stats.record_drop("not-modified")
                    continue

        place = normalize_item(raw_item, theme, stats)
        if place is None:
            continue

        existing = places_by_id.get(place["id"])
        if existing is not None:
            stats.duplicate_content_id_count += 1
            if should_replace(existing, place):
                places_by_id[place["id"]] = place
            continue

        signature = place_signature(place["name"], place["address"], place["latitude"], place["longitude"])
        if signature in signatures:
            stats.duplicate_signature_count += 1
            continue

        places_by_id[place["id"]] = place
        signatures[signature] = place["id"]
        stats.accepted_count += 1
        if limit and len(places_by_id) >= limit:
            break

    if mode == "incremental" and incremental_cutoff is not None and not incremental_supported:
        stats.record_drop("incremental-fallback-full-scan")

    ordered = sorted(places_by_id.values(), key=lambda place: (place["district"], place["category"], place["name"]))
    return ordered, stats


def main() -> None:
    args = parse_args()
    if args.max_places < 0:
        raise SystemExit("--max-places must be 0 or greater.")

    load_env(Path(args.env))
    places, stats = collect(
        source_path=args.source_path,
        source_url=args.source_url,
        mode=args.mode,
        output=args.output,
        max_places=args.max_places,
        strict=args.strict,
        endpoint=args.endpoint,
    )
    status = status_from_stats(stats, len(places))

    if args.dry_run:
        print(
            json.dumps(
                {
                    "providerId": PROVIDER_ID,
                    "providerName": PROVIDER_NAME,
                    "mode": args.mode,
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

    meta_path = write_places_with_metadata(
        Path(args.output),
        places,
        provider_id=PROVIDER_ID,
        provider_name=PROVIDER_NAME,
        status=status,
        no_meta=args.no_meta,
    )
    print(f"wrote {len(places)} places to {args.output}")
    if meta_path:
        print(f"updated meta file {meta_path}")


if __name__ == "__main__":
    main()

#!/usr/bin/env python3
"""Collect full Korea Tour KorService2 data and convert it to Pero places.json."""

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
from datetime import datetime
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
    read_generated_at_from_meta,
    write_places_with_metadata,
)


DEFAULT_ENDPOINT = "https://apis.data.go.kr/B551011/KorService2"
AREA_CODE_PATH = "/areaCode2"
AREA_BASED_LIST_PATH = "/areaBasedList2"
AREA_BASED_SYNC_LIST_PATH = "/areaBasedSyncList2"
DETAIL_COMMON_PATH = "/detailCommon2"
DETAIL_INTRO_PATH = "/detailIntro2"
DETAIL_IMAGE_PATH = "/detailImage2"
DETAIL_PET_PATH = "/detailPetTour2"
PROVIDER_ID = "koreaTour"
PROVIDER_NAME = "한국관광공사 API 동기화 캐시"
MOBILE_OS = "ETC"
MOBILE_APP = "PeroETL"
DEFAULT_CONTENT_TYPE_IDS = [12, 14, 15, 28, 32, 38]
EXCLUDED_THEME_TAGS = {"카페", "커피", "식사", "맛집", "브런치", "디저트", "음식점"}
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
    "한우거리",
    "국밥",
    "횟집",
    "족발",
}
FOOD_CATEGORY_KEYWORDS = {
    "음식점",
    "식당",
    "레스토랑",
    "카페",
    "베이커리",
    "주점",
}
CONTENT_TYPE_LABELS = {
    12: "관광지",
    14: "문화시설",
    15: "행사/공연/축제",
    28: "레포츠",
    32: "숙박",
    38: "쇼핑",
    39: "음식점",
}
SUMMARY_MAX_LENGTH = 400


@dataclass
class AreaCode:
    code: str
    name: str


@dataclass
class CollectStats:
    request_count: int = 0
    detail_request_count: int = 0
    api_error_count: int = 0
    parse_error_count: int = 0
    raw_item_count: int = 0
    accepted_count: int = 0
    duplicate_content_id_count: int = 0
    duplicate_signature_count: int = 0
    area_count: int = 0
    sigungu_count: int = 0
    failures_by_reason: Counter[str] = field(default_factory=Counter)

    def record_drop(self, reason: str) -> None:
        self.failures_by_reason[reason] += 1

    def to_dict(self) -> dict[str, Any]:
        return {
            "requestCount": self.request_count,
            "detailRequestCount": self.detail_request_count,
            "apiErrorCount": self.api_error_count,
            "parseErrorCount": self.parse_error_count,
            "rawItemCount": self.raw_item_count,
            "acceptedCount": self.accepted_count,
            "droppedCount": sum(self.failures_by_reason.values()),
            "duplicateContentIdCount": self.duplicate_content_id_count,
            "duplicateSignatureCount": self.duplicate_signature_count,
            "areaCount": self.area_count,
            "sigunguCount": self.sigungu_count,
            "droppedByReason": dict(sorted(self.failures_by_reason.items())),
        }


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--env", default=str(ROOT_DIR / ".env"), help="Path to .env file")
    parser.add_argument("--output", default=str(DEFAULT_OUTPUT), help="Output places.json path")
    parser.add_argument("--endpoint", default=os.environ.get("KOREA_TOUR_ENDPOINT", DEFAULT_ENDPOINT), help="KorService2 service URL")
    parser.add_argument("--mode", choices=["full", "incremental"], default="full", help="Collection mode")
    parser.add_argument("--modified-since", default="", help="YYYYMMDDHHMMSS override for incremental mode")
    parser.add_argument("--max-places", type=int, default=0, help="Maximum unique places to write. 0 means unlimited")
    parser.add_argument("--num-of-rows", type=int, default=100, help="Rows requested per API page")
    parser.add_argument("--pause", type=float, default=0.05, help="Delay between API calls in seconds")
    parser.add_argument("--progress", action="store_true", help="Print progress logs to stderr during collection")
    parser.add_argument("--area-codes", nargs="*", default=[], help="Optional TourAPI area code filter")
    parser.add_argument("--no-meta", action="store_true", help="Skip metadata sidecar generation")
    parser.add_argument("--dry-run", action="store_true", help="Print stats and samples without writing")
    parser.add_argument("--strict", action="store_true", help="Stop on API/network errors instead of continuing")
    return parser.parse_args()


def normalize_service_key(value: str) -> str:
    normalized = normalize_text(value)
    if "%" in normalized:
        return urllib.parse.unquote(normalized)
    return normalized


def request_json(endpoint: str, path: str, params: dict[str, str]) -> dict[str, Any]:
    url = f"{endpoint.rstrip('/')}{path}?{urllib.parse.urlencode(params)}"
    request = urllib.request.Request(url)
    with urllib.request.urlopen(request, timeout=20) as response:
        return json.loads(response.read().decode("utf-8"))


def request_page(
    endpoint: str,
    service_key: str,
    *,
    area_code: str,
    sigungu_code: str | None,
    content_type_id: int,
    page: int,
    num_of_rows: int,
) -> dict[str, Any]:
    params = {
        "serviceKey": normalize_service_key(service_key),
        "MobileOS": MOBILE_OS,
        "MobileApp": MOBILE_APP,
        "_type": "json",
        "arrange": "A",
        "areaCode": area_code,
        "contentTypeId": str(content_type_id),
        "numOfRows": str(num_of_rows),
        "pageNo": str(page),
    }
    if sigungu_code:
        params["sigunguCode"] = sigungu_code
    return request_json(endpoint, AREA_BASED_LIST_PATH, params)


def request_sync_page(
    endpoint: str,
    service_key: str,
    *,
    modified_since: str,
    page: int,
    num_of_rows: int,
) -> dict[str, Any]:
    params = {
        "serviceKey": normalize_service_key(service_key),
        "MobileOS": MOBILE_OS,
        "MobileApp": MOBILE_APP,
        "_type": "json",
        "modifiedtime": modified_since,
        "numOfRows": str(num_of_rows),
        "pageNo": str(page),
    }
    return request_json(endpoint, AREA_BASED_SYNC_LIST_PATH, params)


def request_detail(
    endpoint: str,
    service_key: str,
    path: str,
    *,
    content_id: str,
    content_type_id: str | None = None,
    extra_params: dict[str, str] | None = None,
) -> dict[str, Any]:
    params = {
        "serviceKey": normalize_service_key(service_key),
        "MobileOS": MOBILE_OS,
        "MobileApp": MOBILE_APP,
        "_type": "json",
        "contentId": content_id,
    }
    if content_type_id:
        params["contentTypeId"] = content_type_id
    if extra_params:
        params.update(extra_params)
    return request_json(endpoint, path, params)


def response_items(payload: dict[str, Any]) -> tuple[list[dict[str, Any]], int]:
    top_level_result_code = str(payload.get("resultCode", "")).strip()
    if top_level_result_code and top_level_result_code != "0000":
        raise RuntimeError(f"{top_level_result_code}:{payload.get('resultMsg', 'UNKNOWN_ERROR')}")

    response = payload.get("response")
    if not isinstance(response, dict):
        raise ValueError("response object is missing")

    header = response.get("header", {})
    result_code = str(header.get("resultCode", "")).strip()
    if result_code not in {"", "0000"}:
        raise RuntimeError(f"{result_code}:{header.get('resultMsg')}")

    body = response.get("body")
    if not isinstance(body, dict):
        return [], 0

    items = body.get("items")
    raw_items = items.get("item", []) if isinstance(items, dict) else []
    if isinstance(raw_items, dict):
        raw_items = [raw_items]
    if raw_items == "":
        raw_items = []
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
    return "|".join([normalized_name, normalized_address, f"{latitude:.4f}", f"{longitude:.4f}"])


def compact_string_map(source: dict[str, Any], keys: list[str]) -> dict[str, str]:
    normalized: dict[str, str] = {}
    for key in keys:
        value = normalize_text(source.get(key))
        if value:
            normalized[key] = value
    return normalized


def compact_all_string_fields(source: dict[str, Any], excluded_keys: set[str] | None = None) -> dict[str, str]:
    normalized: dict[str, str] = {}
    skip = excluded_keys or set()
    for key, value in source.items():
        if key in skip:
            continue
        normalized_value = normalize_text(value)
        if normalized_value:
            normalized[key] = normalized_value
    return normalized


def fetch_area_codes(endpoint: str, service_key: str, area_codes: list[str] | None = None) -> list[AreaCode]:
    params = {
        "serviceKey": normalize_service_key(service_key),
        "MobileOS": MOBILE_OS,
        "MobileApp": MOBILE_APP,
        "_type": "json",
        "numOfRows": "100",
        "pageNo": "1",
    }
    items, _ = response_items(request_json(endpoint, AREA_CODE_PATH, params))
    codes = [AreaCode(code=normalize_text(item.get("code")), name=normalize_text(item.get("name"))) for item in items]
    filtered = [item for item in codes if item.code and item.name]
    if area_codes:
        wanted = set(area_codes)
        filtered = [item for item in filtered if item.code in wanted]
    return filtered


def fetch_sigungu_codes(endpoint: str, service_key: str, area_code: str) -> list[AreaCode]:
    params = {
        "serviceKey": normalize_service_key(service_key),
        "MobileOS": MOBILE_OS,
        "MobileApp": MOBILE_APP,
        "_type": "json",
        "numOfRows": "100",
        "pageNo": "1",
        "areaCode": area_code,
    }
    items, _ = response_items(request_json(endpoint, AREA_CODE_PATH, params))
    return [AreaCode(code=normalize_text(item.get("code")), name=normalize_text(item.get("name"))) for item in items if normalize_text(item.get("code"))]


def content_type_label(content_type_id: str, fallback_category: str) -> str:
    try:
        parsed = int(content_type_id)
    except ValueError:
        return fallback_category
    return CONTENT_TYPE_LABELS.get(parsed, fallback_category)


def derive_category(item: dict[str, Any], content_type_id: int) -> str:
    for key in ("contenttypename", "contentTypeName", "cat3Name", "cat2Name"):
        value = normalize_text(item.get(key))
        if value:
            return value
    return CONTENT_TYPE_LABELS.get(content_type_id, "관광정보")


def normalize_tour_common(common_item: dict[str, Any] | None, intro_item: dict[str, Any] | None) -> dict[str, str] | None:
    source_common = common_item or {}
    source_intro = intro_item or {}
    common = {
        "tel": normalize_text(source_common.get("tel") or source_common.get("telname")),
        "homepage": normalize_text(source_common.get("homepage")),
        "overview": normalize_text(source_common.get("overview")),
        "bookTour": normalize_text(source_common.get("booktour")),
        "infoCenter": normalize_text(source_intro.get("infocenter") or source_intro.get("infocenterfood") or source_intro.get("infocenterculture") or source_intro.get("infocenterlodging") or source_intro.get("infocentershopping") or source_intro.get("infocenterleports")),
        "restDate": normalize_text(source_intro.get("restdate") or source_intro.get("restdatefood") or source_intro.get("restdateculture") or source_intro.get("restdateshopping") or source_intro.get("restdateleports")),
        "useTime": normalize_text(source_intro.get("usetime") or source_intro.get("usetimefood") or source_intro.get("usetimeculture") or source_intro.get("usetimeleports") or source_intro.get("usetimefestival") or source_intro.get("checkintime")),
        "parking": normalize_text(source_intro.get("parking") or source_intro.get("parkingfood") or source_intro.get("parkingleports") or source_intro.get("parkingculture") or source_intro.get("parkingshopping")),
        "useFee": normalize_text(source_intro.get("usefee") or source_intro.get("usefeeleports") or source_intro.get("usefeeculture")),
        "refundPolicy": normalize_text(source_intro.get("refundregulation") or source_intro.get("refundregulationshopping")),
        "expGuide": normalize_text(source_intro.get("expguide") or source_intro.get("expagerange")),
        "accomCount": normalize_text(source_intro.get("accomcount") or source_intro.get("roomcount")),
        "chkInTime": normalize_text(source_intro.get("checkintime")),
        "chkOutTime": normalize_text(source_intro.get("checkouttime")),
        "subFacility": normalize_text(source_intro.get("subfacility") or source_intro.get("subevent")),
        "parkingFee": normalize_text(source_intro.get("parkingfee")),
        "scale": normalize_text(source_intro.get("scale") or source_intro.get("scaleshopping")),
        "spendTime": normalize_text(source_intro.get("spendtime")),
        "eventStartDate": normalize_text(source_intro.get("eventstartdate")),
        "eventEndDate": normalize_text(source_intro.get("eventenddate")),
        "playTime": normalize_text(source_intro.get("playtime")),
        "ageLimit": normalize_text(source_intro.get("agelimit") or source_intro.get("ageLimit")),
    }
    compacted = {key: value for key, value in common.items() if value}
    return compacted or None


def normalize_tour_images(items: list[dict[str, Any]]) -> list[dict[str, str]]:
    images: list[dict[str, str]] = []
    for item in items:
        image = compact_string_map(item, ["originimgurl", "smallimageurl", "imgname", "serialnum"])
        if image:
            images.append(
                {
                    "originImgUrl": image.get("originimgurl"),
                    "smallImageUrl": image.get("smallimageurl"),
                    "imgName": image.get("imgname"),
                    "serialNum": image.get("serialnum"),
                }
            )
    return images


def normalize_tour_pet(item: dict[str, Any] | None) -> dict[str, str] | None:
    if not item:
        return None
    pet = {
        "petTursmInfo": normalize_text(item.get("pettursminfo")),
        "acmpyTypeCd": normalize_text(item.get("acmpytypecd")),
        "relaPosesFclty": normalize_text(item.get("relaposesfclty")),
        "relaFrnshPrdlst": normalize_text(item.get("relafrnshprdlst")),
        "etcAcmpyInfo": normalize_text(item.get("etcacmpyinfo")),
        "relaPurcPrdlst": normalize_text(item.get("relapurcprdlst")),
        "acmpyPsblCpam": normalize_text(item.get("acmpypsblcpam")),
    }
    compacted = {key: value for key, value in pet.items() if value}
    return compacted or None


def is_food_focused_place(title: str, category: str, overview: str | None) -> bool:
    normalized_title = normalize_text(title)
    normalized_category = normalize_text(category)
    normalized_overview = normalize_text(overview)

    if any(keyword in normalized_title for keyword in FOOD_TITLE_KEYWORDS):
        return True
    if any(keyword in normalized_category for keyword in FOOD_CATEGORY_KEYWORDS):
        return True
    if not normalized_overview:
        return False
    if any(keyword in normalized_overview for keyword in ("맛집", "브런치", "디저트", "베이커리", "카페거리", "식당가", "먹거리골목", "음식점")):
        return True
    explicit_food_terms = ("막국수", "삼겹살", "찜갈비", "한우", "국밥", "횟집", "족발", "빵집", "제빵")
    return sum(keyword in normalized_overview for keyword in explicit_food_terms) >= 2


def build_tags(title: str, category: str, district: str, common: dict[str, Any] | None) -> list[str]:
    overview = normalize_text((common or {}).get("overview"))
    source = f"{title} {category} {district} {overview}"
    tags: list[str] = [district, category]

    rules = [
        ("행사", ["행사", "축제", "공연", "시즌"]),
        ("축제", ["행사", "축제", "공연", "시즌"]),
        ("문화", ["문화", "전시", "실내", "관람"]),
        ("박물관", ["전시", "문화", "실내", "관람"]),
        ("미술", ["전시", "문화", "데이트", "관람"]),
        ("공원", ["산책", "야외", "휴식", "데이트"]),
        ("숲", ["산책", "야외", "자연", "힐링"]),
        ("정원", ["산책", "자연", "휴식", "데이트"]),
        ("쇼핑", ["쇼핑", "실내", "데이트"]),
        ("백화점", ["쇼핑", "실내", "데이트", "가족"]),
        ("레포츠", ["활동", "체험", "야외", "주말"]),
        ("숙박", ["숙박", "여행", "체류", "예약"]),
        ("관광", ["관광", "나들이", "방문", "데이트"]),
        ("전망", ["전망", "야경", "산책", "사진"]),
    ]

    for needle, candidates in rules:
        if needle in source:
            tags.extend(candidates)

    if "서울" in district:
        tags.append("서울")
    return dedupe_tags(tags, limit=8)


def build_theme_tags(title: str, category: str, district: str, common: dict[str, Any] | None, pet: dict[str, Any] | None) -> list[str]:
    overview = normalize_text((common or {}).get("overview"))
    haystack = " ".join(
        [
            normalize_text(title),
            normalize_text(category),
            normalize_text(district),
            overview,
            normalize_text((common or {}).get("useTime")),
            normalize_text((common or {}).get("parking")),
            normalize_text((common or {}).get("eventStartDate")),
            normalize_text((common or {}).get("eventEndDate")),
            normalize_text((pet or {}).get("petTursmInfo")),
            normalize_text((pet or {}).get("acmpyPsblCpam")),
        ]
    )

    theme_tags: list[str] = []
    if "서울" in district:
        theme_tags.append("서울")
    if any(keyword in haystack for keyword in ("행사", "축제", "공연", "eventstartdate", "eventenddate")):
        theme_tags.append("축제행사")
    if any(keyword in haystack for keyword in ("산책", "공원", "숲", "수목원", "정원", "전망", "한강", "해변", "바다", "호수", "둘레길")):
        theme_tags.append("자연산책")
    if any(keyword in haystack for keyword in ("문화", "전시", "박물관", "미술", "공연", "실내", "관람", "도서관", "복합문화")):
        theme_tags.append("실내데이트")
    if any(keyword in haystack for keyword in ("가족", "아이", "키즈", "체험", "놀이터", "동물")):
        theme_tags.append("가족나들이")
    if any(keyword in haystack for keyword in ("반려", "애견", "펫", "동반", "pet")):
        theme_tags.append("반려동물동반")
    if any(keyword in haystack for keyword in ("무장애", "배리어프리", "휠체어", "장애", "accessible")):
        theme_tags.append("무장애여행")
    return dedupe_tags(theme_tags, limit=8)


def trim_summary(value: str | None, max_length: int = SUMMARY_MAX_LENGTH) -> str:
    summary = normalize_text(value)
    if len(summary) <= max_length:
        return summary
    return summary[:max_length].rstrip()


def build_generated_summary(title: str, category: str, district: str, theme_tags: list[str]) -> str:
    if "축제행사" in theme_tags:
        return f"{district} 권역의 {category} 유형으로, 시즌성 행사와 테마 탐색에 활용할 수 있는 대표 후보입니다."
    if "자연산책" in theme_tags:
        return f"{district} 권역의 {category} 유형으로, 산책이나 야외 나들이 동선에 맞는 대표 후보입니다."
    if "실내데이트" in theme_tags:
        return f"{district} 권역의 {category} 유형으로, 전시·관람 목적 질의와 연결하기 좋은 대표 후보입니다."
    if "가족나들이" in theme_tags:
        return f"{district} 권역의 {category} 유형으로, 가족 단위 체류와 체험 동선에 맞는 대표 후보입니다."
    if "반려동물동반" in theme_tags:
        return f"{district} 권역의 {category} 유형으로, 반려동물 동반 힌트가 있는 관광 후보입니다."
    return f"{district} 권역의 {category} 유형으로, 관광 테마맵 탐색에 활용할 수 있는 대표 후보입니다."


def build_summary(title: str, category: str, district: str, theme_tags: list[str], overview: str | None = None) -> str:
    official_overview = trim_summary(overview)
    if official_overview:
        return official_overview
    return build_generated_summary(title, category, district, theme_tags)


def build_search_hints(name: str, category: str, district: str, address: str, theme_tags: list[str], common: dict[str, Any] | None, pet: dict[str, Any] | None) -> list[str]:
    hints = [
        f"{name}은(는) KorService2 전수 수집 캐시에서 정규화한 {category} 데이터입니다.",
        f"행정권역은 {district}이며 주소는 {address}입니다.",
    ]
    if common:
        if normalize_text(common.get("overview")):
            hints.append(f"상세 설명: {normalize_text(common.get('overview'))}")
        if normalize_text(common.get("useTime")):
            hints.append(f"운영 시간 정보: {normalize_text(common.get('useTime'))}")
        if normalize_text(common.get("parking")):
            hints.append(f"주차 정보: {normalize_text(common.get('parking'))}")
        if normalize_text(common.get("eventStartDate")) or normalize_text(common.get("eventEndDate")):
            hints.append(
                f"행사 기간: {normalize_text(common.get('eventStartDate'))} ~ {normalize_text(common.get('eventEndDate'))}".strip(" ~")
            )
        if normalize_text(common.get("chkInTime")) or normalize_text(common.get("chkOutTime")):
            hints.append(
                f"숙박 체크인/체크아웃: {normalize_text(common.get('chkInTime'))} / {normalize_text(common.get('chkOutTime'))}".strip(" /")
            )
    if pet and normalize_text(pet.get("petTursmInfo") or pet.get("acmpyPsblCpam")):
        hints.append(f"반려동물 동반 정보: {normalize_text(pet.get('petTursmInfo') or pet.get('acmpyPsblCpam'))}")

    if "축제행사" in theme_tags:
        hints.append("행사, 축제, 시즌 테마 같은 자연어 질의와 연결됩니다.")
    elif "실내데이트" in theme_tags:
        hints.append("전시, 문화, 실내 관람 같은 자연어 질의와 연결됩니다.")
    elif "자연산책" in theme_tags:
        hints.append("산책, 전망, 주말 나들이 같은 자연어 질의와 연결됩니다.")
    else:
        hints.append("근처 갈 만한 곳, 방문 후보 같은 탐색형 질의와 연결됩니다.")

    return hints


def fetch_tour_api_details(endpoint: str, service_key: str, item: dict[str, Any], category: str, stats: CollectStats, *, strict: bool) -> dict[str, Any] | None:
    content_id = normalize_text(item.get("contentid"))
    content_type_id = normalize_text(item.get("contenttypeid"))
    if not content_id or not content_type_id:
        return None

    common_item: dict[str, Any] | None = None
    intro_item: dict[str, Any] | None = None
    image_items: list[dict[str, Any]] = []
    pet_item: dict[str, Any] | None = None

    detail_requests = [
        (DETAIL_COMMON_PATH, None, {}, "detail-common"),
        (DETAIL_INTRO_PATH, content_type_id, {}, "detail-intro"),
        (DETAIL_IMAGE_PATH, None, {"imageYN": "Y"}, "detail-image"),
        (DETAIL_PET_PATH, None, {}, "detail-pet"),
    ]

    for path, request_content_type_id, extra_params, reason in detail_requests:
        stats.request_count += 1
        stats.detail_request_count += 1
        try:
            payload = request_detail(
                endpoint,
                service_key,
                path,
                content_id=content_id,
                content_type_id=request_content_type_id,
                extra_params=extra_params,
            )
            items, _ = response_items(payload)
        except RuntimeError as error:
            if strict:
                raise
            stats.api_error_count += 1
            stats.record_drop(f"{reason}:{normalize_text(str(error))}")
            continue
        except (HTTPError, URLError, TimeoutError, ValueError, json.JSONDecodeError):
            if strict:
                raise
            stats.parse_error_count += 1
            stats.record_drop(f"{reason}:parse-error")
            continue

        if path == DETAIL_COMMON_PATH:
            common_item = items[0] if items else None
        elif path == DETAIL_INTRO_PATH:
            intro_item = items[0] if items else None
        elif path == DETAIL_IMAGE_PATH:
            image_items = items
        else:
            pet_item = items[0] if items else None

    common = normalize_tour_common(common_item, intro_item)
    intro = compact_all_string_fields(intro_item or {})
    images = normalize_tour_images(image_items)
    pet = normalize_tour_pet(pet_item)

    return {
        "contentId": content_id,
        "contentTypeId": content_type_id,
        "contentTypeLabel": content_type_label(content_type_id, category),
        "common": common,
        "intro": intro,
        "images": images,
        "pet": pet,
    }


def to_place(item: dict[str, Any], stats: CollectStats, *, endpoint: str, service_key: str, strict: bool) -> dict[str, Any] | None:
    content_id = normalize_text(item.get("contentid"))
    if not content_id:
        stats.record_drop("missing-contentid")
        return None

    title = normalize_text(item.get("title"))
    if not title:
        stats.record_drop("missing-name")
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

    try:
        content_type_id = int(str(item.get("contenttypeid", "")).strip())
    except ValueError:
        stats.record_drop("invalid-content-type")
        return None

    if content_type_id not in DEFAULT_CONTENT_TYPE_IDS:
        stats.record_drop("excluded-content-type")
        return None

    district = extract_district_from_address(address, normalize_text(item.get("areacode")) or "미상")
    category = derive_category(item, content_type_id)
    tour_api = fetch_tour_api_details(endpoint, service_key, item, category, stats, strict=strict)
    common = (tour_api or {}).get("common") or {}
    pet = (tour_api or {}).get("pet") or {}
    overview = normalize_text(common.get("overview"))
    if is_food_focused_place(title, category, overview):
        stats.record_drop("food-focused-place")
        return None

    tags = build_tags(title, category, district, common)
    theme_tags = build_theme_tags(title, category, district, common, pet)
    summary = build_summary(title, category, district, theme_tags, overview)
    search_hints = build_search_hints(title, category, district, address, theme_tags, common, pet)

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


def iso_to_modifiedtime(value: datetime | None) -> str | None:
    if value is None:
        return None
    return value.strftime("%Y%m%d%H%M%S")


def progress_log(enabled: bool, message: str) -> None:
    if enabled:
        print(message, file=sys.stderr, flush=True)


def collect(
    service_key: str,
    *,
    endpoint: str,
    mode: str,
    modified_since: str | None,
    max_places: int,
    num_of_rows: int,
    pause_seconds: float,
    strict: bool,
    progress: bool = False,
    area_codes: list[str] | None = None,
) -> tuple[list[dict[str, Any]], CollectStats]:
    stats = CollectStats()
    limit = max_places if max_places and max_places > 0 else None
    places_by_id: dict[str, dict[str, Any]] = {}
    signatures: dict[str, str] = {}

    def accept_item(raw_item: dict[str, Any]) -> bool:
        place = to_place(raw_item, stats, endpoint=endpoint, service_key=service_key, strict=strict)
        if place is None:
            return False

        existing = places_by_id.get(place["id"])
        if existing is not None:
            stats.duplicate_content_id_count += 1
            if should_replace(existing, place):
                places_by_id[place["id"]] = place
            return False

        signature = place_signature(place["name"], place["address"], place["latitude"], place["longitude"])
        if signature in signatures:
            stats.duplicate_signature_count += 1
            return False

        places_by_id[place["id"]] = place
        signatures[signature] = place["id"]
        stats.accepted_count += 1
        return True

    if mode == "incremental":
        page = 1
        while True:
            stats.request_count += 1
            try:
                payload = request_sync_page(
                    endpoint,
                    service_key,
                    modified_since=modified_since or "19700101000000",
                    page=page,
                    num_of_rows=num_of_rows,
                )
                items, total_count = response_items(payload)
            except (HTTPError, URLError, TimeoutError, ValueError, json.JSONDecodeError, RuntimeError) as error:
                if strict:
                    raise
                progress_log(progress, f"[sync][incremental][error] page={page} reason={normalize_text(str(error)) or type(error).__name__}")
                if isinstance(error, (ValueError, json.JSONDecodeError)):
                    stats.parse_error_count += 1
                    stats.record_drop("sync:parse-error")
                else:
                    stats.api_error_count += 1
                    stats.record_drop(f"sync:{normalize_text(str(error)) or 'api-error'}")
                break

            if not items:
                break

            stats.raw_item_count += len(items)
            progress_log(progress, f"[sync][incremental] page={page} fetched={len(items)} totalAccepted={stats.accepted_count}")
            for item in items:
                if normalize_text(item.get("contenttypeid")) not in {str(value) for value in DEFAULT_CONTENT_TYPE_IDS}:
                    stats.record_drop("excluded-content-type")
                    continue
                if area_codes and normalize_text(item.get("areacode")) not in set(area_codes):
                    stats.record_drop("excluded-area-code")
                    continue
                accept_item(item)
                if limit and len(places_by_id) >= limit:
                    break
            if limit and len(places_by_id) >= limit:
                break
            if page * num_of_rows >= total_count:
                break
            page += 1
            time.sleep(pause_seconds)
    else:
        resolved_area_codes = fetch_area_codes(endpoint, service_key, area_codes)
        stats.area_count = len(resolved_area_codes)
        progress_log(progress, f"[sync][full] areas={stats.area_count} contentTypes={','.join(str(value) for value in DEFAULT_CONTENT_TYPE_IDS)}")
        for area in resolved_area_codes:
            sigungu_codes = fetch_sigungu_codes(endpoint, service_key, area.code)
            if sigungu_codes:
                stats.sigungu_count += len(sigungu_codes)
                sigungu_values = [item.code for item in sigungu_codes]
            else:
                stats.sigungu_count += 1
                sigungu_values = [None]

            progress_log(
                progress,
                f"[sync][full][area] areaCode={area.code} areaName={area.name} sigunguCount={len(sigungu_values)} accepted={stats.accepted_count}"
            )

            for sigungu_code in sigungu_values:
                for content_type_id in DEFAULT_CONTENT_TYPE_IDS:
                    page = 1
                    while True:
                        stats.request_count += 1
                        try:
                            payload = request_page(
                                endpoint,
                                service_key,
                                area_code=area.code,
                                sigungu_code=sigungu_code,
                                content_type_id=content_type_id,
                                page=page,
                                num_of_rows=num_of_rows,
                            )
                            items, total_count = response_items(payload)
                        except (HTTPError, URLError, TimeoutError, ValueError, json.JSONDecodeError, RuntimeError) as error:
                            if strict:
                                raise
                            progress_log(
                                progress,
                                f"[sync][full][error] areaCode={area.code} sigunguCode={sigungu_code or '-'} contentType={content_type_id} page={page} reason={normalize_text(str(error)) or type(error).__name__}"
                            )
                            if isinstance(error, (ValueError, json.JSONDecodeError)):
                                stats.parse_error_count += 1
                                stats.record_drop("area:parse-error")
                            else:
                                stats.api_error_count += 1
                                stats.record_drop(f"area:{normalize_text(str(error)) or 'api-error'}")
                            break

                        if not items:
                            break

                        stats.raw_item_count += len(items)
                        progress_log(
                            progress,
                            f"[sync][full][page] areaCode={area.code} sigunguCode={sigungu_code or '-'} contentType={content_type_id} page={page} fetched={len(items)} totalCount={total_count} accepted={stats.accepted_count}"
                        )
                        for item in items:
                            accept_item(item)
                            if limit and len(places_by_id) >= limit:
                                break
                        if limit and len(places_by_id) >= limit:
                            break
                        if page * num_of_rows >= total_count:
                            break
                        page += 1
                        time.sleep(pause_seconds)
                    if limit and len(places_by_id) >= limit:
                        break
                    time.sleep(pause_seconds)
                if limit and len(places_by_id) >= limit:
                    break
            if limit and len(places_by_id) >= limit:
                break

    ordered = sorted(places_by_id.values(), key=lambda place: (place["district"], place["category"], place["name"]))
    return ordered, stats


def main() -> None:
    args = parse_args()
    if args.max_places < 0:
        raise SystemExit("--max-places must be 0 or greater.")
    if args.num_of_rows < 1:
        raise SystemExit("--num-of-rows must be greater than 0.")

    load_env(Path(args.env))
    service_key = os.environ.get("KOREA_TOUR_API_SERVICE_KEY") or os.environ.get("KOREA_TOUR_API_KEY")
    if not service_key:
        raise SystemExit("KOREA_TOUR_API_SERVICE_KEY is missing. Add it to .env.")
    endpoint = os.environ.get("KOREA_TOUR_ENDPOINT", args.endpoint)

    modified_since = normalize_text(args.modified_since)
    if args.mode == "incremental" and not modified_since:
        modified_dt = read_generated_at_from_meta(Path(args.output))
        modified_since = iso_to_modifiedtime(modified_dt) or "19700101000000"

    places, stats = collect(
        service_key,
        endpoint=endpoint,
        mode=args.mode,
        modified_since=modified_since,
        max_places=args.max_places,
        num_of_rows=args.num_of_rows,
        pause_seconds=args.pause,
        strict=args.strict,
        progress=args.progress,
        area_codes=args.area_codes,
    )
    status = status_from_stats(stats, len(places))

    if args.dry_run:
        print(
            json.dumps(
                {
                    "providerId": PROVIDER_ID,
                    "providerName": PROVIDER_NAME,
                    "mode": args.mode,
                    "modifiedSince": modified_since or None,
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

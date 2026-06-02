#!/usr/bin/env python3
"""Unified place cache synchronization entrypoint."""

from __future__ import annotations

import argparse
import json
import os
from pathlib import Path

from korservice2_to_pero import (
    DEFAULT_ENDPOINT,
    DEFAULT_OUTPUT as DEFAULT_KOREA_OUTPUT,
    collect as collect_korea_tour,
    load_env,
    status_from_stats as korea_tour_status,
    write_places_with_metadata,
)
from smartseoul_to_pero import (
    DEFAULT_SMART_OUTPUT,
    collect as collect_smart_seoul,
    status_from_stats as smart_seoul_status,
)


PROVIDER_NAMES = {
    "koreaTour": "한국관광공사 API 동기화 캐시",
    "smartSeoul": "스마트서울맵 캐시",
}
DEFAULT_OUTPUTS = {
    "koreaTour": DEFAULT_KOREA_OUTPUT,
    "smartSeoul": DEFAULT_SMART_OUTPUT,
}


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--provider", default="koreaTour", choices=["koreaTour", "smartSeoul"], help="Synchronize selected provider cache.")
    parser.add_argument("--env", default=str((Path(__file__).resolve().parents[2] / ".env")), help="Path to .env file")
    parser.add_argument("--output", default="", help="Output cache path. Defaults to provider-specific file.")
    parser.add_argument("--endpoint", default=DEFAULT_ENDPOINT, help="KorService2 service base URL")
    parser.add_argument("--mode", choices=["full", "incremental"], default="full", help="Collection mode")
    parser.add_argument("--modified-since", default="", help="YYYYMMDDHHMMSS override for incremental KoreaTour mode")
    parser.add_argument("--max-places", type=int, default=0, help="Maximum unique places to write. 0 means unlimited")
    parser.add_argument("--num-of-rows", type=int, default=100, help="Rows requested per API page")
    parser.add_argument("--pause", type=float, default=0.05, help="Delay between API calls in seconds")
    parser.add_argument("--progress", action="store_true", help="Print progress logs to stderr during collection")
    parser.add_argument("--area-codes", nargs="*", default=[], help="Optional TourAPI area code filter")
    parser.add_argument("--source-path", default="", help="Smart Seoul source file path override")
    parser.add_argument("--source-url", default="", help="Smart Seoul source URL override")
    parser.add_argument("--no-meta", action="store_true", help="Skip metadata sidecar generation")
    parser.add_argument("--dry-run", action="store_true", help="Print stats and samples without writing")
    parser.add_argument("--strict", action="store_true", help="Stop on API/network errors instead of continuing")
    return parser.parse_args()


def main() -> None:
    args = parse_args()
    load_env(Path(args.env))

    output = Path(args.output) if args.output else Path(DEFAULT_OUTPUTS[args.provider])

    if args.provider == "koreaTour":
        service_key = os.environ.get("KOREA_TOUR_API_SERVICE_KEY") or os.environ.get("KOREA_TOUR_API_KEY")
        if not service_key:
            raise SystemExit("KOREA_TOUR_API_SERVICE_KEY is missing. Add it to .env.")
        places, stats = collect_korea_tour(
            service_key,
            endpoint=os.environ.get("KOREA_TOUR_ENDPOINT", args.endpoint),
            mode=args.mode,
            modified_since=args.modified_since,
            max_places=args.max_places,
            num_of_rows=args.num_of_rows,
            pause_seconds=args.pause,
            strict=args.strict,
            progress=args.progress,
            area_codes=args.area_codes,
        )
        status = korea_tour_status(stats, len(places))
    else:
        places, stats = collect_smart_seoul(
            source_path=args.source_path,
            source_url=args.source_url,
            mode=args.mode,
            output=str(output),
            max_places=args.max_places,
            strict=args.strict,
        )
        status = smart_seoul_status(stats, len(places))

    if args.dry_run:
        print(
            json.dumps(
                {
                    "providerId": args.provider,
                    "providerName": PROVIDER_NAMES[args.provider],
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
        output,
        places,
        provider_id=args.provider,
        provider_name=PROVIDER_NAMES[args.provider],
        status=status,
        no_meta=args.no_meta,
    )
    print(f"wrote {len(places)} places to {output}")
    if meta_path:
        print(f"updated meta file {meta_path}")


if __name__ == "__main__":
    main()

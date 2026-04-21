#!/usr/bin/env python3
"""Unified place cache synchronization entrypoint."""

from __future__ import annotations

import argparse
import json
import os
from pathlib import Path

from korservice2_to_pero import (
    DEFAULT_OUTPUT,
    DEFAULT_ENDPOINT,
    collect,
    load_env,
    status_from_stats,
    write_places_with_metadata,
)


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--provider",
        default="koreaTour",
        choices=["koreaTour", "smartSeoul"],
        help="Synchronize selected provider cache.",
    )
    parser.add_argument("--env", default=str((Path(__file__).resolve().parents[2] / ".env")), help="Path to .env file")
    parser.add_argument("--output", default=str(DEFAULT_OUTPUT), help="Output places.json path")
    parser.add_argument(
        "--endpoint",
        default=DEFAULT_ENDPOINT,
        help="KorService2 service base URL",
    )
    parser.add_argument("--max-places", type=int, default=120, help="Maximum unique places to write")
    parser.add_argument("--num-of-rows", type=int, default=50, help="Rows requested per API page")
    parser.add_argument("--pause", type=float, default=0.15, help="Delay between API calls in seconds")
    parser.add_argument(
        "--regions",
        nargs="*",
        default=[],
        help="Optional KorTour target names. Default: all configured targets.",
    )
    parser.add_argument(
        "--region-target",
        type=int,
        default=0,
        help="Max unique places per target. 0 means derived from --max-places.",
    )
    parser.add_argument("--no-meta", action="store_true", help="Skip metadata sidecar generation")
    parser.add_argument("--dry-run", action="store_true", help="Print stats and samples without writing")
    parser.add_argument("--strict", action="store_true", help="Stop on API/network errors instead of continuing")
    return parser.parse_args()


def main() -> None:
    args = parse_args()
    if args.provider != "koreaTour":
        raise SystemExit(
            "smartSeoul provider collector is prepared for schema compatibility but not implemented yet. "
            "Use --provider=koreaTour for now."
        )

    if args.max_places < 1:
        raise SystemExit("--max-places must be greater than 0.")
    if args.num_of_rows < 1:
        raise SystemExit("--num-of-rows must be greater than 0.")

    load_env(Path(args.env))

    service_key = os.environ.get("KOREA_TOUR_API_SERVICE_KEY") or os.environ.get("KOREA_TOUR_API_KEY")
    if not service_key:
        raise SystemExit("KOREA_TOUR_API_SERVICE_KEY is missing. Add it to .env.")

    places, stats = collect(
        service_key,
        endpoint=args.endpoint,
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
                    "providerId": "koreaTour",
                    "providerName": "한국관광공사 API 동기화 캐시",
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
        provider_id="koreaTour",
        provider_name="한국관광공사 API 동기화 캐시",
        status=status,
        no_meta=args.no_meta,
    )
    print(f"wrote {len(places)} places to {args.output}")
    if meta_path:
        print(f"updated meta file {meta_path}")


if __name__ == "__main__":
    main()

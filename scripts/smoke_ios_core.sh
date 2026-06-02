#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CORE_PACKAGE="$ROOT_DIR/ios/PeroCore"

echo "== Pero iOS core smoke =="
echo "root: $ROOT_DIR"
echo "package: $CORE_PACKAGE"

if [[ ! -f "$CORE_PACKAGE/Package.swift" ]]; then
  echo "ERROR: missing $CORE_PACKAGE/Package.swift" >&2
  exit 1
fi

echo "-- Swift package manifest --"
swift package --package-path "$CORE_PACKAGE" dump-package >/tmp/pero-core-package.json
jq -r '.name as $name | "package=\($name) targets=\([.targets[].name] | join(","))"' /tmp/pero-core-package.json

echo "-- Swift build --"
swift build --package-path "$CORE_PACKAGE"

echo "-- Swift tests --"
swift test --package-path "$CORE_PACKAGE"

if command -v swift-format >/dev/null 2>&1; then
  echo "-- Swift format lint --"
  swift-format lint --recursive "$CORE_PACKAGE/Sources" "$CORE_PACKAGE/Tests"
else
  echo "-- Swift format lint --"
  echo "swift-format not installed; using swift build/test compiler diagnostics as lint fallback"
fi

if [[ -x "$ROOT_DIR/backend/gradlew" ]]; then
  echo "-- Backend API/provider contract tests --"
  "$ROOT_DIR/backend/gradlew" -p "$ROOT_DIR/backend" test
else
  echo "-- Backend API/provider contract tests --"
  echo "SKIP: backend/gradlew is not executable"
fi

echo "== PASS: Pero iOS core smoke =="

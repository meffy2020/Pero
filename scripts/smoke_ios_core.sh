#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CORE_PACKAGE="$ROOT_DIR/ios/PeroCore"
IOS_PROJECT="$ROOT_DIR/ios/Pero.xcodeproj"
IOS_SCHEME="Pero"
IOS_TEST_DESTINATION="${IOS_TEST_DESTINATION:-}"

printf '== Pero iOS MVP smoke ==\n'
printf 'root: %s\n' "$ROOT_DIR"
printf 'package: %s\n' "$CORE_PACKAGE"
printf 'project: %s\n' "$IOS_PROJECT"

if [[ ! -f "$CORE_PACKAGE/Package.swift" ]]; then
  echo "ERROR: missing $CORE_PACKAGE/Package.swift" >&2
  exit 1
fi

if [[ ! -d "$IOS_PROJECT" ]]; then
  echo "ERROR: missing $IOS_PROJECT" >&2
  exit 1
fi

echo "-- Swift package manifest --"
swift package --package-path "$CORE_PACKAGE" dump-package >/tmp/pero-core-package.json
jq -r '.name as $name | "package=\($name) targets=\([.targets[].name] | join(","))"' /tmp/pero-core-package.json

echo "-- Swift package build --"
swift build --package-path "$CORE_PACKAGE"

echo "-- Swift package tests --"
swift test --package-path "$CORE_PACKAGE"

if command -v swift-format >/dev/null 2>&1; then
  echo "-- Swift format lint --"
  swift-format lint --recursive "$CORE_PACKAGE/Sources" "$CORE_PACKAGE/Tests"
else
  echo "-- Swift format lint --"
  echo "swift-format not installed; using swift build/test compiler diagnostics as lint fallback"
fi

echo "-- Xcode project list --"
xcodebuild -list -project "$IOS_PROJECT"

echo "-- Xcode simulator build --"
xcodebuild -project "$IOS_PROJECT" -scheme "$IOS_SCHEME" -destination 'generic/platform=iOS Simulator' build

echo "-- Xcode simulator tests --"
if [[ -z "$IOS_TEST_DESTINATION" ]]; then
  IOS_TEST_DESTINATION="$(xcodebuild -project "$IOS_PROJECT" -scheme "$IOS_SCHEME" -showdestinations 2>/dev/null \
    | sed -n 's/.*{ platform:iOS Simulator,.* id:\([0-9A-F-][0-9A-F-]*\),.*name:\([^}]*\) }.*/id=\1/p' \
    | head -n 1)"
fi
if [[ -z "$IOS_TEST_DESTINATION" ]]; then
  echo "ERROR: could not resolve an available iOS Simulator destination" >&2
  exit 1
fi
echo "destination: $IOS_TEST_DESTINATION"
xcodebuild -project "$IOS_PROJECT" -scheme "$IOS_SCHEME" -destination "$IOS_TEST_DESTINATION" test

echo "-- Backend API/provider contract tests --"
if [[ ! -x "$ROOT_DIR/backend/gradlew" ]]; then
  echo "ERROR: backend/gradlew is missing or not executable" >&2
  exit 1
fi
"$ROOT_DIR/backend/gradlew" -p "$ROOT_DIR/backend" test

echo "== PASS: Pero iOS MVP smoke =="

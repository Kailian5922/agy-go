#!/usr/bin/env bash
# Builds an Android APK for AGY Go with an automatic monotonic build number.
#
# Usage:
#   bash tooling/build-apk.sh                 # release arm64 APK
#   bash tooling/build-apk.sh --debug         # debug arm64 APK
#   bash tooling/build-apk.sh --abi x64       # x86_64 emulator APK
set -euo pipefail

HERE="$(CDPATH= cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(dirname "$HERE")"
MODE="release"
ABI="arm64"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --debug) MODE="debug" ;;
    --release) MODE="release" ;;
    --abi) ABI="${2:?missing abi}"; shift ;;
    -h|--help)
      echo "Usage: $0 [--debug|--release] [--abi arm64|x64|all]"
      exit 0
      ;;
    *)
      echo "Unknown option: $1" >&2
      exit 1
      ;;
  esac
  shift
done

case "$ABI" in
  arm64) TARGET="android-arm64" ;;
  x64) TARGET="android-x64" ;;
  all) TARGET="android-arm64,android-x64" ;;
  *) echo "Unsupported ABI: $ABI" >&2; exit 1 ;;
esac

# Monotonic build number: (year - 2026) * 1e8 + MMDDhhmm (UTC+8)
BUILD_NUM="$(python3 -c 'import datetime; t=datetime.datetime.now(datetime.timezone(datetime.timedelta(hours=8))); print((t.year-2026)*100000000 + t.month*1000000 + t.day*10000 + t.hour*100 + t.minute)')"

echo "[build-apk] mode=$MODE target=$TARGET build-number=$BUILD_NUM"
cd "$ROOT/app"
flutter pub get
flutter build apk "--$MODE" --target-platform "$TARGET" --build-number "$BUILD_NUM"
echo "[build-apk] output: $ROOT/app/build/app/outputs/flutter-apk/app-$MODE.apk"

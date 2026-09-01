#!/usr/bin/env bash
# Type-check the whole module against iOS 9.0 without generating code.
#
# This is what turns the compat-shim guesswork into a list: the compiler names
# every API that does not exist at this deployment target, which a grep cannot
# do (it cannot see availability, overload resolution, or protocol conformance).
set -uo pipefail
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
BUILD="${BUILD:-$HOME/legacy-ios9/build}"
LOG_DIR="${LOG_DIR:-$HOME/legacy-ios9/logs}"
mkdir -p "$BUILD/generated" "$BUILD/staging/Opaline.app" "$LOG_DIR"
STAMP="$(date +%Y%m%d-%H%M%S)"
LOG="$LOG_DIR/typecheck-$STAMP.log"
ln -sfn "$LOG" "$LOG_DIR/typecheck-latest.log"
exec > >(stdbuf -oL -eL tee -a "$LOG") 2>&1

SDK="${SDK:-$HOME/legacy-ios9/toolchain/xc12/Xcode.app/Contents/Developer/Platforms/iPhoneOS.platform/Developer/SDKs/iPhoneOS14.5.sdk}"
TARGET="${TARGET:-armv7-apple-ios9.3}"
MANIFEST="$BUILD/generated/LegacyAssetManifest.swift"

echo "[$(date +%H:%M:%S)] generating asset manifest"
python3 "$REPO/scripts/legacy/flatten-assets.py" \
    --catalog "$REPO/Opaline/Assets.xcassets" \
    --out "$BUILD/staging/Opaline.app" --manifest "$MANIFEST" >/dev/null || exit 1

mapfile -t SOURCES < <("$REPO/scripts/legacy/build.sh" --sources)
echo "[$(date +%H:%M:%S)] type-checking ${#SOURCES[@]} files for $TARGET"
echo "  (-wmo is required, not an optimisation: without it the driver stops"
echo "   scheduling jobs after the first failing batch and under-reports badly"
echo "   -- 6 errors against a true 223.)"
time "$REPO/scripts/legacy/darling-swiftc" -typecheck -wmo \
    -target "$TARGET" -sdk "$SDK" -module-name Opaline \
    -swift-version 5 -D LEGACY_IOS9 \
    "${SOURCES[@]}"
RC=${PIPESTATUS[0]}
echo "[$(date +%H:%M:%S)] typecheck exit: ${RC:-?}"

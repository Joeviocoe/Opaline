#!/usr/bin/env bash
# Package the staged armv7 app as an .ipa for sideloading.
#
# The repo's top-level make_ipa.sh drives xcodebuild and needs macOS. This one
# takes what scripts/legacy/build.sh + bundle-runtime.sh already produced --
# an ldid-signed Opaline.app with the Swift runtime bundled -- and zips it as
# Payload/Opaline.app, which is all an .ipa is. No codesign, no ibtool, no
# macOS: the bundle is already fake-signed for a jailbroken device.
#
# For AppSync/Filza installs, and for handing a testable build to someone whose
# hardware we do not have (issue #1: iPhone 5c/16:9).
#
#   ./make_ipa.sh                 package the current staging dir
#   ./make_ipa.sh --out <path>    write somewhere other than the default
set -uo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
BUILD="${BUILD:-$HOME/legacy-ios9/build}"
STAGING="$BUILD/staging/Opaline.app"
OUT_DIR="${OUT_DIR:-$HOME/legacy-ios9/ipa}"

while [ $# -gt 0 ]; do
    case "$1" in
        --out) OUT_DIR="$2"; shift 2 ;;
        *) echo "unknown arg: $1" >&2; exit 2 ;;
    esac
done

log() { printf '[%s] %s\n' "$(date +%H:%M:%S)" "$*"; }

if [ ! -d "$STAGING" ]; then
    echo "no staged app at $STAGING -- run build.sh first" >&2
    exit 1
fi

# Version comes from the bundle itself, so the filename can never disagree
# with what the device will report after installing it.
read -r VERSION BUILD_NO < <(python3 - "$STAGING/Info.plist" <<'PY'
import plistlib, sys
d = plistlib.load(open(sys.argv[1], 'rb'))
print(d.get('CFBundleShortVersionString', '0.0.0'), d.get('CFBundleVersion', '0'))
PY
)

mkdir -p "$OUT_DIR"
IPA="$OUT_DIR/Opaline_${VERSION}-ios9.ipa"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

log "staging  $STAGING"
log "version  $VERSION (build $BUILD_NO)"

mkdir -p "$WORK/Payload"
cp -a "$STAGING" "$WORK/Payload/Opaline.app"

# -y keeps symlinks as symlinks: the Swift runtime in Frameworks/ relies on
# them, and resolving them would both bloat the ipa and break the dylib layout.
rm -f "$IPA"
( cd "$WORK" && zip -qry "$IPA" Payload ) || { echo "zip failed" >&2; exit 1; }

log "wrote    $IPA ($(du -h "$IPA" | cut -f1))"
log ""
log "install on a jailbroken device with AppSync Unified:"
log "  Filza -> tap the .ipa -> Install"
log "or over USB:  ideviceinstaller -i $(basename "$IPA")"

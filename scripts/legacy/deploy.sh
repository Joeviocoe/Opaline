#!/usr/bin/env bash
# Everything between a finished build.sh and a testable app on the iPad.
#
#   ./deploy.sh              bundle -> .deb -> repo index -> serve -> logs
#   ./deploy.sh --check      show what it would do, start nothing
#   ./deploy.sh --no-serve   package only (useful when the tunnel is already up)
#
# This exists because the four steps have four separate gotchas, every one of
# which fails *quietly* -- the app installs, launches, and simply behaves like
# the change was never made:
#
#   * make_bundle.py writes build/staging/Opaline.app, but make_deb.sh defaults
#     APP_PATH to build/Opaline.app, which does not exist. Passing the wrong one
#     packages nothing new.
#   * the bundle is NOT refreshed by build.sh. Skipping make_bundle.py packages
#     whatever binary was staged last time.
#   * the .deb version comes from MARKETING_VERSION in the pbxproj (1.11.0),
#     which is BELOW what is already installed. APT reads that as a downgrade
#     and Cydia silently offers no upgrade. The version is bumped from the repo
#     here instead.
#   * a byte-compare of the staged binary against build/Opaline always fails --
#     bundle-runtime.sh ldid-signs it. Check CFBundleVersion, not bytes.
set -uo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
BUILD="${BUILD:-$HOME/legacy-ios9/build}"
REPO_DIR="${REPO_DIR:-$HOME/legacy-ios9/repo}"
APP="$BUILD/staging/Opaline.app"
BIN="$BUILD/Opaline"
LOG_DIR="${LOG_DIR:-$HOME/legacy-ios9/logs}"
mkdir -p "$LOG_DIR"
export OPENSSL_CONF="${OPENSSL_CONF:-$HOME/openssl_legacy.cnf}"

log() { printf '[%s] %s\n' "$(date +%H:%M:%S)" "$*"; }
die() { log "ERROR: $*"; exit 1; }

CHECK=0; SERVE=1
for a in "$@"; do
    case "$a" in
        --check) CHECK=1 ;;
        --no-serve) SERVE=0 ;;
    esac
done

[ -f "$BIN" ] || die "no binary at $BIN -- run scripts/legacy/build.sh first"
log "binary   $BIN ($(date -r "$BIN" +%H:%M:%S), $(du -h "$BIN" | cut -f1))"

# Next version = highest already in the repo, patch bumped. Cydia only offers an
# upgrade for a strictly greater version, and the pbxproj value is lower than
# what is installed.
HIGHEST="$(ls -1 "$REPO_DIR/debs"/*.deb 2>/dev/null \
    | sed -n 's/.*_\([0-9.]*\)-ios9_.*/\1/p' | sort -V | tail -1)"
if [ -z "$HIGHEST" ]; then
    NEXT="1.0.0"
else
    NEXT="$(echo "$HIGHEST" | awk -F. '{printf "%d.%d.%d", $1, $2, $3+1}')"
fi
STAMP="$(date +%Y%m%d%H%M)"
log "version  $HIGHEST -> $NEXT (build $STAMP)"

if [ "$CHECK" -eq 1 ]; then
    log "=== check only, nothing done"
    exit 0
fi

log "=== 1/4 bundle (also lipos + ldid-signs the Swift runtime)"
BUNDLE_BUILD="$STAMP" python3 "$REPO/scripts/legacy/make_bundle.py" \
    >>"$LOG_DIR/deploy-$STAMP.log" 2>&1 || die "make_bundle.py failed (see $LOG_DIR/deploy-$STAMP.log)"
[ -d "$APP" ] || die "no bundle at $APP"

# The real freshness check. Bytes differ from build/Opaline because of signing.
GOT="$(grep -a -A1 CFBundleVersion "$APP/Info.plist" | sed -n 's/.*<string>\(.*\)<\/string>.*/\1/p' | head -1)"
[ "$GOT" = "$STAMP" ] || die "bundle stamped '$GOT', expected '$STAMP' -- stale bundle"
log "         staged, CFBundleVersion=$GOT"

log "=== 2/4 package"
APP_PATH="$APP" DEB_VERSION="$NEXT" bash "$REPO/scripts/legacy/make_deb.sh" \
    >>"$LOG_DIR/deploy-$STAMP.log" 2>&1 || die "make_deb.sh failed"
DEB="$REPO_DIR/debs/Opaline_${NEXT}-ios9_iphoneos-arm.deb"
[ -f "$DEB" ] || die "expected $DEB"
log "         $DEB ($(du -h "$DEB" | cut -f1))"

log "=== 3/4 index"
python3 "$REPO/scripts/legacy/make_repo.py" --root "$REPO_DIR" \
    >>"$LOG_DIR/deploy-$STAMP.log" 2>&1 || die "make_repo.py failed"

if [ "$SERVE" -eq 0 ]; then
    log "=== done (--no-serve)"
    exit 0
fi

log "=== 4/4 serve + logs"
bash "$REPO/scripts/legacy/serve-repo.sh" start 2>&1 | sed 's/^/         /'
bash "$REPO/scripts/legacy/devlog.sh" start >/dev/null 2>&1 && log "         devlog up"
bash "$REPO/scripts/legacy/keylog.sh" start 2>&1 | sed 's/^/         /'

log ""
log "Cydia -> Sources -> http://127.0.0.1:8080/  -> upgrade to $NEXT-ios9"
log "then:  scripts/legacy/keylog.sh watch"

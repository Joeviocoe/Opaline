#!/usr/bin/env bash
# Stage the PUBLIC GitHub Pages repo: newest deb only, source icon, landing page.
#
# Kept separate from ~/legacy-ios9/repo so serve-repo.sh keeps working against
# the full local archive while this holds only what gets published.
#
#   ./make_pages_repo.sh [--version 1.11.0] [--stage DIR]
set -uo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
VERSION=""                            # empty -> the fork's own line, resolved below
STAGE="$HOME/legacy-ios9/pages-repo"
LOG_DIR="${LOG_DIR:-$HOME/legacy-ios9/logs}"; mkdir -p "$LOG_DIR"
APP_PATH="${APP_PATH:-$HOME/legacy-ios9/build/staging/Opaline.app}"
ICON_SRC="$REPO/Opaline/Assets.xcassets/AppIconOpaline.appiconset/Icon-1024.png"

while [ $# -gt 0 ]; do
    case "$1" in
        --version) VERSION="$2"; shift 2 ;;
        --stage)   STAGE="$2";   shift 2 ;;
        *) echo "unknown arg: $1" >&2; exit 2 ;;
    esac
done

# This fork is version-independent of upstream: it cannot run on upstream's
# hardware, so MARKETING_VERSION (upstream's 1.11.0) is meaningless here.
# deploy.sh drives the version off the local deb archive; match that exactly so
# what gets published is the same build that was tested on the device.
if [ -z "$VERSION" ]; then
    VERSION="$(ls -1 "$HOME/legacy-ios9/repo/debs"/*.deb 2>/dev/null \
        | sed -n 's/.*_\([0-9.]*\)-ios9_.*/\1/p' | sort -V | tail -1)"
    [ -n "$VERSION" ] || VERSION="1.0.0"
fi

log() { printf '[%s] %s\n' "$(date +%H:%M:%S)" "$*"; }
fail() { log "ERROR: $*"; exit 1; }

log "=== 1. prerequisites"
[ -d "$APP_PATH" ] || fail "no app bundle at $APP_PATH -- build first"
log "app bundle   $APP_PATH ($(du -sh "$APP_PATH" | cut -f1))"
[ -f "$ICON_SRC" ] || fail "no master icon at $ICON_SRC"
log "icon source  $(basename "$ICON_SRC")"

RESIZER=""
if python3 -c "import PIL" 2>/dev/null; then RESIZER="pil"
elif command -v magick >/dev/null; then RESIZER="magick"
elif command -v convert >/dev/null; then RESIZER="convert"
fi
[ -n "$RESIZER" ] || log "WARNING: no PIL/ImageMagick -- CydiaIcon.png will be skipped"
log "resizer      ${RESIZER:-none}"

log "=== 2. clean stage"
rm -rf "$STAGE"
mkdir -p "$STAGE/debs" || fail "cannot create $STAGE"
log "stage        $STAGE"

log "=== 3. cut the deb (version $VERSION, Section: Multimedia)"
APP_PATH="$APP_PATH" DEB_VERSION="$VERSION" OUT_DIR="$STAGE/debs" \
    bash "$REPO/scripts/legacy/make_deb.sh" >"$LOG_DIR/pages-deb.log" 2>&1 \
    || { tail -25 "$LOG_DIR/pages-deb.log"; fail "make_deb.sh failed"; }
DEB=$(ls "$STAGE"/debs/*.deb 2>/dev/null | head -1)
[ -n "$DEB" ] || fail "make_deb.sh produced no .deb"
log "deb          $(basename "$DEB") ($(du -h "$DEB" | cut -f1))"

log "=== 4. CydiaIcon.png (repo icon in Cydia's Sources list)"
if [ "$RESIZER" = "pil" ]; then
    python3 - "$ICON_SRC" "$STAGE/CydiaIcon.png" <<'PY'
import sys
from PIL import Image
src, dst = sys.argv[1], sys.argv[2]
im = Image.open(src).convert("RGBA").resize((128, 128), Image.LANCZOS)
im.save(dst, "PNG", optimize=True)
PY
elif [ -n "$RESIZER" ]; then
    "$RESIZER" "$ICON_SRC" -resize 128x128 "$STAGE/CydiaIcon.png"
fi
[ -f "$STAGE/CydiaIcon.png" ] && log "icon         CydiaIcon.png 128x128"

log "=== 5. index + Packages/Release"
python3 "$REPO/scripts/legacy/make_repo.py" --root "$STAGE" || fail "make_repo.py failed"

# make_repo.py writes its own index.html; replace it with one carrying the
# source URL and the legacy-root note.
cat > "$STAGE/index.html" <<'HTML'
<!doctype html><meta charset=utf-8>
<meta name=viewport content="width=device-width,initial-scale=1">
<title>Opaline Legacy &mdash; iOS 9 repo</title>
<style>
 body{font:15px/1.6 -apple-system,system-ui,sans-serif;max-width:34em;
      margin:2.5em auto;padding:0 1.2em;color:#1a1a1a;background:#fafafa}
 code{background:#ececec;padding:.15em .4em;border-radius:3px;font-size:.9em}
 .u{display:block;background:#ececec;padding:.7em;border-radius:5px;
    word-break:break-all;margin:1em 0}
 .n{border-left:3px solid #c8a000;background:#fffbe8;padding:.8em 1em;
    margin:1.6em 0;font-size:.93em}
 h1{font-size:1.35em;margin-bottom:.2em} .s{color:#666;margin-top:0}
</style>
<h1>Opaline &mdash; iOS 9 / armv7</h1>
<p class=s>Lightweight YouTube client for 32-bit A5/A5X hardware:
   iPad 2/3, iPad mini 1, iPhone 4S, iPod touch 5.</p>
<p>Add this URL as a source in Cydia, Zebra or Sileo:</p>
<code class=u>https://joeviocoe.github.io/Opaline/</code>
<div class=n><strong>iOS 9 and lower:</strong> if the source fails to add,
  your jailbreak did not ship modern root certificates. Install
  <a href="https://tlsroot.litten.ca/">Hanabi's Updated Root CAs</a>
  and try again. Carbon already includes them.</div>
<p>SponsorBlock, offline downloads, subscriptions and playlists.
   No ads, no tracking, no dependencies.</p>
HTML
touch "$STAGE/.nojekyll"          # serve the tree raw; no Jekyll pipeline
log "index        index.html + .nojekyll"

log "=== done"
echo
echo "stage: $STAGE"
find "$STAGE" -type f | sort | sed "s#$STAGE#  .#"
echo
echo "total: $(du -sh "$STAGE" | cut -f1)"

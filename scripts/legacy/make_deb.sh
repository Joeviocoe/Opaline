#!/usr/bin/env bash
# Package the armv7 build as a Cydia/Sileo .deb, entirely on Linux.
#
# A .deb is just an ar archive of debian-binary + control.tar.gz + data.tar.gz,
# so no dpkg is required.  Upstream's make_deb.sh uses bsdtar spellings
# (--uid/--gid/--format gnutar) that GNU tar rejects; this uses the GNU
# equivalents (--owner/--group/--format=gnu) so it runs on Fedora as-is.
#
#   ./make_deb.sh [--stub]     --stub packages a placeholder payload, which
#                              exercises the whole path before a real binary
#                              exists.
# Env: APP_PATH, DEB_VERSION, OUT_DIR
set -uo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
OUT_DIR="${OUT_DIR:-$HOME/legacy-ios9/repo/debs}"
LOG_DIR="${LOG_DIR:-$HOME/legacy-ios9/logs}"
mkdir -p "$OUT_DIR" "$LOG_DIR"
LOG="$LOG_DIR/deb-$(date +%Y%m%d-%H%M%S).log"
exec > >(stdbuf -oL -eL tee -a "$LOG") 2>&1
log() { printf '[%s] %s\n' "$(date +%H:%M:%S)" "$*"; }

# Overridable so the same packaging path builds the armv7 toolchain gate app
# as well as Opaline itself -- one script, so the gate really does exercise
# the path the real package will take.
APP_NAME="${APP_NAME:-Opaline}"
# Distinct from upstream's com.verback.ytlite so APT never offers this armv7
# build to an arm64 iOS 12 user -- Architecture: iphoneos-arm covers both.
PACKAGE_ID="${PACKAGE_ID:-com.verback.ytlite.legacy}"
VERSION="${DEB_VERSION:-$(sed -n 's/.*MARKETING_VERSION = \([^;]*\);.*/\1/p' \
    "$REPO/Opaline.xcodeproj/project.pbxproj" | head -1)}"
VERSION="${VERSION:-1.11.0}-ios9"

STUB=0; [ "${1:-}" = "--stub" ] && STUB=1
APP_PATH="${APP_PATH:-$HOME/legacy-ios9/build/$APP_NAME.app}"

STAGE=$(mktemp -d); trap 'rm -rf "$STAGE"' EXIT
DATA="$STAGE/data"; CTRL="$STAGE/control"
mkdir -p "$DATA/Applications" "$CTRL"

log "package  $PACKAGE_ID"
log "version  $VERSION"
log "out      $OUT_DIR"

if [ "$STUB" -eq 1 ]; then
    log "STUB payload -- proving the packaging and repo path without a binary"
    mkdir -p "$DATA/Applications/$APP_NAME.app"
    printf 'stub\n' > "$DATA/Applications/$APP_NAME.app/$APP_NAME"
    chmod 0755 "$DATA/Applications/$APP_NAME.app/$APP_NAME"
    cat > "$DATA/Applications/$APP_NAME.app/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleExecutable</key><string>Opaline</string>
  <key>CFBundleIdentifier</key><string>com.verback.YTLite</string>
  <key>CFBundleName</key><string>Opaline</string>
  <key>MinimumOSVersion</key><string>9.0</string>
  <key>UIRequiredDeviceCapabilities</key><array><string>armv7</string></array>
  <key>UIDeviceFamily</key><array><integer>1</integer><integer>2</integer></array>
  <key>LSRequiresIPhoneOS</key><true/>
</dict></plist>
PLIST
else
    [ -d "$APP_PATH" ] || { log "ERROR: no app bundle at $APP_PATH (build first, or pass --stub)"; exit 1; }
    log "payload  $APP_PATH"
    cp -a "$APP_PATH" "$DATA/Applications/"
fi

SIZE_KB=$(du -sk "$DATA" | cut -f1)

# Only the real package supersedes upstream's; the gate app must not claim to.
CONFLICTS="${CONFLICTS-Conflicts: com.verback.ytlite\nReplaces: com.verback.ytlite\n}"
CONFLICTS=$(printf '%b' "$CONFLICTS")
DESCRIPTION="${DESCRIPTION:-Description: Lightweight YouTube client for 32-bit iOS 9 devices
 armv7 build for A5/A5X hardware: iPad 2/3, iPad mini 1, iPhone 4S,
 iPod touch 5.  SponsorBlock, offline downloads, subscriptions and
 playlists.  No ads, no tracking, no dependencies.}"

cat > "$CTRL/control" <<EOF
Package: $PACKAGE_ID
Name: $APP_NAME (iOS 9)
Version: $VERSION
Architecture: iphoneos-arm
Section: Applications
Priority: optional
Depends: firmware (>= 9.0), firmware (<< 12.0)
${CONFLICTS}Installed-Size: $SIZE_KB
Maintainer: legacy-ios9 build
Author: verback2308
Homepage: https://github.com/verback2308/Opaline
$DESCRIPTION
EOF

# iOS 9's uicache takes NO arguments.  Upstream runs `uicache -p ... || uicache
# -a || true`, so on iOS 9 both branches fail, `|| true` swallows it, and the
# icon never appears.  The bare form is the one that works here.
cat > "$CTRL/postinst" <<EOF
#!/bin/sh
uicache -p "/Applications/$APP_NAME.app" 2>/dev/null \\
  || uicache -a 2>/dev/null \\
  || uicache 2>/dev/null \\
  || true
exit 0
EOF
cat > "$CTRL/postrm" <<'EOF'
#!/bin/sh
uicache -a 2>/dev/null || uicache 2>/dev/null || true
exit 0
EOF
chmod 0755 "$CTRL/postinst" "$CTRL/postrm"

OUTPUT="$OUT_DIR/${APP_NAME}_${VERSION}_iphoneos-arm.deb"
printf '2.0\n' > "$STAGE/debian-binary"
# GNU tar equivalents of upstream's bsdtar flags.
TARFLAGS=(--owner=0 --group=0 --numeric-owner --format=gnu)
tar -czf "$STAGE/control.tar.gz" "${TARFLAGS[@]}" -C "$CTRL" ./control ./postinst ./postrm || exit 1
tar -czf "$STAGE/data.tar.gz"    "${TARFLAGS[@]}" -C "$DATA" . || exit 1
rm -f "$OUTPUT"
( cd "$STAGE" && ar rc "$OUTPUT" debian-binary control.tar.gz data.tar.gz ) || exit 1

log "built    $OUTPUT ($(du -h "$OUTPUT" | cut -f1))"
log "members  $(ar t "$OUTPUT" | tr '\n' ' ')"
echo "$OUTPUT"

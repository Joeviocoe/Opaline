#!/bin/bash
# make_deb.sh — packages the app built by make_ipa.sh into Cydia/Sileo .deb files
# Usage: ./make_ipa.sh && ./make_deb.sh
# Output: Opaline_<version>_iphoneos-arm.deb   (rootful,  /Applications)
#         Opaline_<version>_iphoneos-arm64.deb (rootless, /var/jb/Applications)
#
# Requires only stock macOS tools (bsdtar + ar) — no dpkg needed. The app is
# taken as-is from the build products, so it carries the fixed ad-hoc
# signature applied by make_ipa.sh (keychain items survive updates).
#
# Env overrides (all optional):
#   APP_PATH     path to the built Opaline.app (default: from build settings)
#   DEB_VERSION  package version (default: CFBundleShortVersionString of the app)

set -e

APP_NAME="Opaline"
PROJECT="Opaline.xcodeproj"
SCHEME="Opaline"
PACKAGE_ID="com.verback.ytlite"
HOMEPAGE="https://github.com/verback2308/ytlite"
ICON_URL="https://raw.githubusercontent.com/verback2308/ytlite/main/source/icon.png"

if [ -z "${APP_PATH:-}" ]; then
  BUILD_DIR=$(xcodebuild \
    -project "$PROJECT" \
    -scheme "$SCHEME" \
    -sdk iphoneos \
    -configuration Release \
    -showBuildSettings 2>/dev/null |
    grep "^ *BUILT_PRODUCTS_DIR" | head -1 | awk -F' = ' '{print $2}')
  APP_PATH="$BUILD_DIR/$APP_NAME.app"
fi

if [ ! -d "$APP_PATH" ]; then
  echo "❌ App not found at: $APP_PATH — run ./make_ipa.sh first"
  exit 1
fi

VERSION="${DEB_VERSION:-$(plutil -extract CFBundleShortVersionString raw -o - "$APP_PATH/Info.plist")}"

# $1 = architecture, $2 = install prefix ("" rootful, /var/jb rootless), $3 = min firmware
build_deb() {
  local ARCH="$1" PREFIX="$2" MIN_FW="$3"
  # Named after the app rather than after PACKAGE_ID, which Debian convention
  # would use: the id is frozen at the pre-rename com.verback.ytlite so APT keeps
  # offering upgrades, and putting that on the releases page under a project
  # called Opaline confuses far more people than the broken convention does.
  # Nothing resolves packages by filename -- APT follows Filename: in the index.
  local OUTPUT="${APP_NAME}_${VERSION}_${ARCH}.deb"
  local STAGE
  STAGE=$(mktemp -d)
  local DATA="$STAGE/data" CTRL="$STAGE/control"

  mkdir -p "$DATA$PREFIX/Applications" "$CTRL"
  cp -R "$APP_PATH" "$DATA$PREFIX/Applications/"

  local SIZE_KB
  SIZE_KB=$(du -sk "$DATA" | cut -f1)

  cat > "$CTRL/control" <<EOF
Package: $PACKAGE_ID
Name: $APP_NAME
Version: $VERSION
Architecture: $ARCH
Section: Applications
Priority: optional
Depends: firmware (>= $MIN_FW)
Installed-Size: $SIZE_KB
Maintainer: verback2308
Author: verback2308
Homepage: $HOMEPAGE
Icon: $ICON_URL
Description: Lightweight YouTube client for iOS 12+
 SponsorBlock, Return YouTube Dislike, up to 1080p playback, background
 audio, PiP, subtitles. No ads, no tracking, no dependencies.
EOF

  cat > "$CTRL/postinst" <<EOF
#!/bin/sh
uicache -p "$PREFIX/Applications/$APP_NAME.app" 2>/dev/null || uicache -a || true
exit 0
EOF

  cat > "$CTRL/postrm" <<'EOF'
#!/bin/sh
uicache -a || true
exit 0
EOF
  chmod 0755 "$CTRL/postinst" "$CTRL/postrm"

  # A .deb is an ar archive: debian-binary, control.tar.gz, data.tar.gz —
  # in that order, everything owned by root.
  printf "2.0\n" > "$STAGE/debian-binary"
  tar -czf "$STAGE/control.tar.gz" --format gnutar --uid 0 --gid 0 --numeric-owner \
    -C "$CTRL" ./control ./postinst ./postrm
  tar -czf "$STAGE/data.tar.gz" --format gnutar --uid 0 --gid 0 --numeric-owner \
    -C "$DATA" .

  rm -f "$OUTPUT"
  (cd "$STAGE" && ar rc "$OLDPWD/$OUTPUT" debian-binary control.tar.gz data.tar.gz)
  rm -rf "$STAGE"

  echo "✅ $OUTPUT ($(du -sh "$OUTPUT" | cut -f1))"
}

echo "▶ Packaging debs for $VERSION from $APP_PATH"
build_deb iphoneos-arm "" 12.0
build_deb iphoneos-arm64 /var/jb 15.0

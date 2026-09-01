#!/usr/bin/env bash
# Rebuild the Fedora/Qubes build environment for the armv7 / iOS 9 downport.
#
# This VM discards package installs on reboot: in a Qubes AppVM only /home,
# /rw and /usr/local survive, everything else is restored from the template.
# So dnf packages must be reinstalled each boot, while anything we *build*
# goes into a persistent prefix and survives.
#
#   ./setup-env.sh --check     report what is present/missing (no changes, no sudo)
#   ./setup-env.sh --packages  dnf install the package layer (needs sudo)
#   ./setup-env.sh --tools     build/fetch the non-packaged tools into the prefix
#   ./setup-env.sh --all       both, in order
#
# Idempotent: every step is skipped when its output already exists.
set -uo pipefail

LOG_DIR="${LOG_DIR:-$HOME/legacy-ios9/logs}"
TOOLS="${TOOLS:-$HOME/legacy-ios9/toolchain}"
mkdir -p "$LOG_DIR" "$TOOLS"
LOG="$LOG_DIR/setup-$(date +%Y%m%d-%H%M%S).log"

# Everything is tee'd, so a long run can be watched over SSH with:
#   tail -f ~/legacy-ios9/logs/setup-*.log
exec > >(tee -a "$LOG") 2>&1
say() { printf '\n[%s] == %s\n' "$(date +%H:%M:%S)" "$*"; }
note() { printf '[%s]    %s\n' "$(date +%H:%M:%S)" "$*"; }

# ---------------------------------------------------------------- prefix
# Prefer /usr/local: Qubes bind-mounts it from /rw/usrlocal, so it persists
# and is on PATH already.  Fall back to ~/.local when it is not writable.
if [ -w /usr/local/bin ] || sudo -n true 2>/dev/null; then
    PREFIX=/usr/local
    SUDO=sudo
else
    PREFIX="$HOME/.local"
    SUDO=""
fi
mkdir -p "$PREFIX/bin" 2>/dev/null || { PREFIX="$HOME/.local"; SUDO=""; mkdir -p "$PREFIX/bin"; }

# Fedora packages.  libimobiledevice gives us device access and logs; the rest
# are build deps for ldid / cctools-port / pbzx, plus the .deb and .xip tools.
PKGS=(
  git make cmake automake autoconf libtool pkgconf-pkg-config
  gcc gcc-c++ clang lld llvm
  openssl-devel libxml2-devel zlib-devel libzstd-devel bzip2-devel
  libplist libplist-devel
  libimobiledevice libimobiledevice-utils usbmuxd ideviceinstaller
  bsdtar cpio xar dpkg fakeroot
  python3 xz
)

# tool -> what provides it, for the status report
declare -A PROVIDER=(
  [git]=pkg [gcc]=pkg [cmake]=pkg [clang]=pkg [bsdtar]=pkg [cpio]=pkg
  [xar]=pkg [dpkg]=pkg [fakeroot]=pkg [idevicesyslog]=pkg [ideviceinstaller]=pkg
  [ldid]=built [lipo]=built [otool]=built [ld64]=built [vtool]=built
  [pbzx]=built [swiftc]=fetched
)

status() {
    say "environment status   (prefix: $PREFIX)"
    note "persistent paths: /home  /rw  /usr/local   [Qubes AppVM]"
    note "logs: $LOG_DIR"
    note "tools: $TOOLS"
    printf '\n    %-18s %-9s %s\n' TOOL SOURCE PATH
    for t in "${!PROVIDER[@]}"; do :; done
    for t in git gcc cmake clang bsdtar cpio xar dpkg fakeroot \
             idevicesyslog ideviceinstaller ldid lipo otool ld64 vtool pbzx swiftc; do
        p=$(command -v "$t" 2>/dev/null || true)
        [ -z "$p" ] && [ -x "$TOOLS/swift/usr/bin/$t" ] && p="$TOOLS/swift/usr/bin/$t"
        printf '    %-18s %-9s %s\n' "$t" "${PROVIDER[$t]:-?}" "${p:-MISSING}"
    done
    echo
    note "Xcode 13.4.1 SDK: $([ -d "$TOOLS/xcode13" ] && echo "$TOOLS/xcode13" || echo 'NOT EXTRACTED - see Phase 0 step 1')"
    note "device: $(timeout 5 idevice_id -l 2>/dev/null | head -1 || true)"
    note "usbmuxd: $(pgrep -c usbmuxd 2>/dev/null || true) process(es)"
}

packages() {
    say "installing ${#PKGS[@]} packages (lost on VM reset, so re-run after reboot)"
    $SUDO dnf install -y --setopt=install_weak_deps=False "${PKGS[@]}"
    note "dnf exit: $?"
    say "enabling usbmuxd for device access"
    $SUDO systemctl enable --now usbmuxd 2>/dev/null || note "usbmuxd: start manually if needed"
}

build_ldid() {
    command -v ldid >/dev/null && { note "ldid present, skipping"; return; }
    say "building ldid (fake-signing for the jailbroken device)"
    local d="$TOOLS/src/ldid"
    rm -rf "$d"; mkdir -p "$d"
    git clone --depth 1 https://github.com/ProcursusTeam/ldid.git "$d" || return 1
    make -C "$d" -j"$(nproc)" || return 1
    $SUDO install -m 0755 "$d/ldid" "$PREFIX/bin/ldid" && note "installed $PREFIX/bin/ldid"
}

build_cctools() {
    command -v lipo >/dev/null && { note "cctools present, skipping"; return; }
    say "building cctools-port (lipo, otool, ld64, strip, vtool for Mach-O)"
    local d="$TOOLS/src/cctools-port"
    rm -rf "$d"; mkdir -p "$d"
    git clone --depth 1 https://github.com/tpoechtrager/cctools-port.git "$d" || return 1
    ( cd "$d/cctools" && ./configure --prefix="$PREFIX" --target=arm-apple-darwin11 \
        && make -j"$(nproc)" && $SUDO make install ) || return 1
    note "installed cctools into $PREFIX/bin"
}

build_pbzx() {
    command -v pbzx >/dev/null && { note "pbzx present, skipping"; return; }
    say "building pbzx (unpacks the Xcode .xip payload)"
    local d="$TOOLS/src/pbzx"
    rm -rf "$d"; mkdir -p "$d"
    git clone --depth 1 https://github.com/NiklasRosenstein/pbzx.git "$d" || return 1
    ( cd "$d" && clang -O2 -llzma -lxar -I/usr/local/include -L/usr/local/lib \
        -o pbzx pbzx.c ) || return 1
    $SUDO install -m 0755 "$d/pbzx" "$PREFIX/bin/pbzx" && note "installed $PREFIX/bin/pbzx"
}

fetch_swift() {
    [ -x "$TOOLS/swift/usr/bin/swiftc" ] && { note "swift toolchain present, skipping"; return; }
    say "fetching swift.org Linux 5.6.1 toolchain (Route B of the toolchain gate)"
    note "5.6.1 is the last Swift that can target armv7-apple-ios"
    local url="https://download.swift.org/swift-5.6.1-release/ubuntu2004/swift-5.6.1-RELEASE/swift-5.6.1-RELEASE-ubuntu20.04.tar.gz"
    mkdir -p "$TOOLS/swift"
    curl -fL --progress-bar "$url" -o "$TOOLS/swift.tar.gz" || {
        note "download failed - fetch manually into $TOOLS/swift.tar.gz"; return 1; }
    tar -xzf "$TOOLS/swift.tar.gz" -C "$TOOLS/swift" --strip-components=1 || return 1
    rm -f "$TOOLS/swift.tar.gz"
    note "swiftc: $TOOLS/swift/usr/bin/swiftc"
}

tools() {
    build_ldid   || note "ldid FAILED - see log"
    build_cctools|| note "cctools FAILED - see log"
    build_pbzx   || note "pbzx FAILED - see log"
    fetch_swift  || note "swift FAILED - see log"
    say "adding $PREFIX/bin and the swift toolchain to PATH for future shells"
    local rc="$HOME/.bashrc"
    grep -q 'legacy-ios9/toolchain/swift' "$rc" 2>/dev/null || cat >> "$rc" <<EOF

# armv7 / iOS 9 downport toolchain
export PATH="$PREFIX/bin:$TOOLS/swift/usr/bin:\$PATH"
export LEGACY_TOOLS="$TOOLS"
EOF
}

case "${1:---check}" in
    --check)    status ;;
    --packages) packages; status ;;
    --tools)    tools; status ;;
    --all)      packages; tools; status ;;
    *) echo "usage: $0 [--check|--packages|--tools|--all]"; exit 2 ;;
esac
say "done - full log at $LOG"

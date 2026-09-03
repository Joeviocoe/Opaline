#!/usr/bin/env bash
# Bring the armv7/iOS 9 build environment back up after a Qubes AppVM reset.
#
# Only /home, /rw and /usr/local survive a reset here — everything else
# (dnf packages, /usr, SELinux relabeling state) is restored from the
# template. This script exists because that loses three things that are
# each individually silent until something downstream fails in a confusing
# way, sometimes minutes later:
#
#   1. dnf packages (git, clang, cmake, the device tools, ...)
#   2. Darling's install under /usr, including every executable bit in it
#   3. darlingserver's running state, which the VM reset kills mid-session
#
# Usage:
#   ./cold-boot.sh            run everything, in order
#   ./cold-boot.sh --check    report what is missing without changing anything
#
# Idempotent: every step below detects whether it already ran and skips if so,
# so this is also safe to re-run mid-session if something looks wrong.
set -uo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
LOG_DIR="${LOG_DIR:-$HOME/legacy-ios9/logs}"
mkdir -p "$LOG_DIR"
LOG="$LOG_DIR/cold-boot-$(date +%Y%m%d-%H%M%S).log"
exec > >(tee -a "$LOG") 2>&1

say() { printf '\n[%s] == %s\n' "$(date +%H:%M:%S)" "$*"; }
note() { printf '[%s]    %s\n' "$(date +%H:%M:%S)" "$*"; }
die() { printf '[%s]    ERROR: %s\n' "$(date +%H:%M:%S)" "$*"; exit 1; }

CHECK=0
[ "${1:-}" = "--check" ] && CHECK=1

# ---------------------------------------------------------------------------
# Step 1: dnf packages, cctools, the fetched Swift toolchain.
#
# libdispatch-devel is not in setup-env.sh's own package list. Without it
# cctools-port's ./configure fails with "Required library libblocksruntime
# not installed" -- found 2026-09-03. It is otherwise harmless to install
# whether or not cctools ends up mattering to a given session (bundle-runtime
# .sh uses Apple's own lipo via Darling, not the cctools-port one -- but
# setup-env.sh still tries to build the latter, and a failed sub-step there
# does not fail the overall script, it just leaves a MISLEADING "MISSING" in
# the status table for tools nothing on the real build path uses).
# ---------------------------------------------------------------------------
say "step 1: system packages + cctools + swiftc"
if [ "$CHECK" -eq 1 ]; then
    bash "$REPO/scripts/legacy/setup-env.sh" --check
else
    sudo dnf install -y libdispatch-devel
    bash "$REPO/scripts/legacy/setup-env.sh" --all
fi

# ---------------------------------------------------------------------------
# Step 2: Darling itself. Not covered by setup-env.sh at all -- it is not a
# dnf package on Fedora (see darling-on-fedora.md), so it lives entirely
# under /usr from a prior manual install, and a VM reset wipes /usr.
#
# The already-extracted deb payload persists under /home from a previous
# session (~/legacy-ios9/darling-debs/root/), so this is a re-copy, not a
# re-download.
# ---------------------------------------------------------------------------
say "step 2: darling (translation layer for Apple's own swift-frontend)"
DARLING_SRC="$HOME/legacy-ios9/darling-debs/root/usr"
if command -v darling >/dev/null 2>&1 && [ -x /usr/bin/darling ]; then
    note "darling binary already present, skipping the copy"
elif [ "$CHECK" -eq 1 ]; then
    note "darling: $(command -v darling || echo MISSING)"
else
    [ -d "$DARLING_SRC" ] || die "no extracted darling payload at $DARLING_SRC -- see darling-on-fedora.md for the download+extract steps"

    # NEVER cp -a here. It preserves ownership and SELinux context, which
    # relabels /usr/bin, /usr/lib etc. as user:user + user_home_t -- SELinux
    # then blocks PAM's setuid unix_chkpwd and sudo dies with "account
    # validation failure, is your account locked?" pkexec still works, so
    # that trap IS recoverable, but --no-preserve=all avoids it outright.
    note "copying darling into /usr (this takes a few seconds, ~740MB)"
    sudo cp -r --no-preserve=all "$DARLING_SRC/." /usr/

    # --no-preserve=all does not just skip ownership/context -- it also
    # skips the executable bit on every regular file, unconditionally.
    # Measured: 33,478 executables in the source tree, 33,476 landed
    # -rw-r--r-- at the destination. Restore them from the source tree's
    # own bits, in one batched pass rather than 33k individual chmods.
    note "restoring executable bits (cp --no-preserve=all drops them on ~all files)"
    find "$DARLING_SRC" -type f -perm -u+x -printf '%P\0' \
        | sed -z "s|^|/usr/|" \
        | xargs -0 -P4 -n200 sudo chmod +x

    sudo chmod 755 /usr/bin/darling /usr/bin/darlingserver
    # setuid: darling creates Linux namespaces for its container, which
    # needs privilege it does not otherwise have.
    sudo chmod u+s /usr/bin/darling

    # Sanity check the SELinux-avoidance actually worked, and that root's own
    # authentication was not collateral damage.
    sudo -n true || die "sudo just broke -- check SELinux contexts on /usr with: ls -Zd /usr /usr/bin /usr/lib"
    note "darling installed; sudo still healthy; contexts untouched"
fi

# ---------------------------------------------------------------------------
# Step 3: darlingserver's per-user runtime state. The daemon (and any
# in-progress container boot) dies with the VM, but partial/interrupted
# attempts from earlier in a session (e.g. one that failed on step 2's
# now-fixed exec-bit problem) can leave ~/.darling in a state where the next
# `darling shell` fails FAST with "Error connecting to shellspawn in the
# container: ... No such file or directory" and an empty dserver.log -- not
# hung, just wedged. `darling shutdown` clears it unconditionally; harmless
# to run even when nothing is running.
# ---------------------------------------------------------------------------
say "step 3: reset darling's runtime state and do one real boot"
if [ "$CHECK" -eq 1 ]; then
    note "(skipped under --check)"
else
    darling shutdown >/dev/null 2>&1 || true
    OUT="$(timeout 60 darling shell uname -a 2>&1)"
    RC=$?
    note "darling shell uname -a -> $OUT"
    if [ $RC -ne 0 ] || [ "${OUT#Darwin}" = "$OUT" ]; then
        die "darling did not boot cleanly (expected a line starting with 'Darwin'). Re-run this script; if it repeats, see darling-reinstall-after-reset.md"
    fi
fi

# ---------------------------------------------------------------------------
# Step 4: prove the actual compiler the build depends on works, not just
# darling in the abstract. This is Apple Swift 5.4.2 from the Xcode 12.5.1
# payload at ~/legacy-ios9/toolchain/xc12/, which -- unlike darling itself --
# lives under /home and survives a reset untouched.
# ---------------------------------------------------------------------------
say "step 4: verify the real compiler wrapper"
if [ "$CHECK" -eq 1 ]; then
    [ -x "$REPO/scripts/legacy/darling-swiftc" ] && note "darling-swiftc: present" || note "darling-swiftc: MISSING"
else
    bash "$REPO/scripts/legacy/darling-swiftc" -version \
        || die "darling-swiftc failed even though darling itself booted -- check that xc12/Xcode.app is still at \$HOME/legacy-ios9/toolchain/xc12/"
fi

# ---------------------------------------------------------------------------
# Step 5: device link (read-only checks only -- this script never installs
# or modifies anything on the iPad).
# ---------------------------------------------------------------------------
say "step 5: device link"
export OPENSSL_CONF="${OPENSSL_CONF:-$HOME/openssl_legacy.cnf}"
UDID="$(timeout 10 idevice_id -l 2>/dev/null)"
if [ -n "$UDID" ]; then
    note "device: $UDID"
else
    note "no device seen (idevice_id -l empty) -- fine if the iPad is not plugged in yet; scripts/legacy/ipad.sh and serve-repo.sh will re-check when actually needed"
fi

say "cold boot done -- log at $LOG"
if [ "$CHECK" -eq 0 ]; then
    note "next: scripts/legacy/typecheck.sh (~20s, the fast loop) or scripts/legacy/build.sh (~4min, the real build)"
    note "device testing: scripts/legacy/deploy.sh takes a finished build to the iPad in one step"
fi

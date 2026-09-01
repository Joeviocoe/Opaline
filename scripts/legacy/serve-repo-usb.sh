#!/usr/bin/env bash
# Serve the Cydia repo to the iPad over USB, with no TLS and no public hosting.
#
# This AppVM is NAT'd, GitHub Pages force-redirects to HTTPS, and iOS 9.3.5
# cannot validate Let's Encrypt (ISRG Root X1 is iOS 10+).  All of that goes
# away if the device fetches from its OWN loopback:
#
#   Fedora :8080  (python http.server, repo dir)
#        ^
#        | ssh -R 8080:127.0.0.1:8080     <- reverse forward
#        |
#   iPad 127.0.0.1:8080  <- Cydia source
#        ^
#        | iproxy 2222:22 over usbmuxd    <- USB, no network at all
#
# Then in Cydia: Sources -> Edit -> Add -> http://127.0.0.1:8080/
#
# Prereqs on the device: OpenSSH from Cydia.  In Qubes, attach the iPad to this
# VM first from dom0:  qvm-usb attach <thisvm> <backend>:<dev>
#
#   ./serve-repo-usb.sh            start everything, stay in foreground
#   ./serve-repo-usb.sh --check    diagnose the chain without starting anything
set -uo pipefail

REPO_DIR="${REPO_DIR:-$HOME/legacy-ios9/repo}"
LOG_DIR="${LOG_DIR:-$HOME/legacy-ios9/logs}"
SSH_PORT="${SSH_PORT:-2222}"      # local port
DEVICE_SSH="${DEVICE_SSH:-2269}"  # sshd port on the device (OpenSSH from Cydia)
export OPENSSL_CONF="${OPENSSL_CONF:-$HOME/openssl_legacy.cnf}"
HTTP_PORT="${HTTP_PORT:-8080}"    # served here, and reverse-forwarded to the device
DEVICE_USER="${DEVICE_USER:-root}"
mkdir -p "$LOG_DIR"
LOG="$LOG_DIR/serve-$(date +%Y%m%d-%H%M%S).log"
exec > >(stdbuf -oL -eL tee -a "$LOG") 2>&1
log() { printf '[%s] %s\n' "$(date +%H:%M:%S)" "$*"; }

PIDS=()
cleanup() {
    log "shutting down"
    for p in "${PIDS[@]:-}"; do [ -n "$p" ] && kill "$p" 2>/dev/null; done
}
trap cleanup EXIT INT TERM

log "=== 1. usbmuxd"
if ! pgrep -x usbmuxd >/dev/null; then
    log "usbmuxd not running; starting in foreground mode"
    (usbmuxd -f >>"$LOG" 2>&1 &) ; sleep 2
fi
pgrep -x usbmuxd >/dev/null && log "usbmuxd ok" || log "WARNING: usbmuxd not running"

log "=== 2. device"
UDID=$(timeout 8 idevice_id -l 2>/dev/null | head -1)
if [ -z "$UDID" ]; then
    log "NO DEVICE VISIBLE."
    log "  In Qubes, USB devices belong to sys-usb until attached:"
    log "    (dom0) qvm-usb list"
    log "    (dom0) qvm-usb attach $(hostname) sys-usb:<dev>"
    log "  Then unlock the iPad and accept the 'Trust This Computer' prompt."
    [ "${1:-}" = "--check" ] || exit 1
else
    log "device: $UDID"
    NAME=$(timeout 8 ideviceinfo -k DeviceName 2>/dev/null)
    VER=$(timeout 8 ideviceinfo -k ProductVersion 2>/dev/null)
    PROD=$(timeout 8 ideviceinfo -k ProductType 2>/dev/null)
    log "        $NAME / $PROD / iOS $VER"
    [ "$PROD" = "iPad3,1" ] || log "        (note: plan targets iPad3,1 = A1416)"
    timeout 8 idevicepair validate >/dev/null 2>&1 \
        && log "pairing ok" \
        || { log "pairing required -- running idevicepair pair"; timeout 20 idevicepair pair; }
fi

log "=== 3. repo contents"
if [ -f "$REPO_DIR/Packages" ]; then
    log "repo: $REPO_DIR"
    grep -E '^(Package|Version|Filename):' "$REPO_DIR/Packages" | sed 's/^/         /'
else
    log "WARNING: no Packages index at $REPO_DIR -- run make_deb.sh then make_repo.py"
fi

if [ "${1:-}" = "--check" ]; then
    log "=== check only, nothing started"
    exit 0
fi

log "=== 4. http server on :$HTTP_PORT"
( cd "$REPO_DIR" && python3 -m http.server "$HTTP_PORT" --bind 127.0.0.1 ) >>"$LOG" 2>&1 &
PIDS+=($!); sleep 1
curl -sf "http://127.0.0.1:$HTTP_PORT/Packages" >/dev/null \
    && log "serving ok" || log "WARNING: local fetch failed"

log "=== 5. iproxy $SSH_PORT -> device:$DEVICE_SSH (over USB)"
# iproxy changed argument style between releases; try new form, then old.
( iproxy "$SSH_PORT" "$DEVICE_SSH" >>"$LOG" 2>&1 ) &
PIDS+=($!); sleep 2

log "=== 6. reverse tunnel: device 127.0.0.1:$HTTP_PORT -> here"
log "you will be asked for the device root password (default on a fresh"
log "OpenSSH install is 'alpine' -- change it)"
log ""
log "    Cydia -> Sources -> Edit -> Add ->  http://127.0.0.1:$HTTP_PORT/"
log ""
# iOS 9's dropbear/OpenSSH only speaks legacy KEX/MAC/host-key algorithms.
ssh -p "$SSH_PORT" -N \
    -o HostKeyAlgorithms=+ssh-rsa \
    -o PubkeyAcceptedAlgorithms=+ssh-rsa \
    -o KexAlgorithms=+diffie-hellman-group1-sha1,diffie-hellman-group14-sha1 \
    -o MACs=+hmac-sha1,hmac-sha1-96 \
    -o IPQoS=throughput \
    -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
    -o ServerAliveInterval=30 \
    -R "$HTTP_PORT:127.0.0.1:$HTTP_PORT" \
    "$DEVICE_USER@localhost"

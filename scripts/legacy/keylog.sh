#!/usr/bin/env bash
# The app's own log, live over SSH-on-USB.
#
#   ./keylog.sh start [name]   begin capture, detached
#   ./keylog.sh stop
#   ./keylog.sh status
#   ./keylog.sh watch          follow the filtered stream live
#   ./keylog.sh keys           just the [Keys] lines from the capture
#   ./keylog.sh raw [n]        last n raw lines (default 50)
#
# Why this exists rather than devlog.sh: AppLog writes to a rotating file in
# the app's Caches/Logs, and that file is the only place the keyboard tracing
# lands in full. devlog.sh reads the *system* log, which is the right tool for
# a launch that never happens (dyld, amfid, signals) but not for a running app
# talking about itself. Run both.
#
# Four things this gets right, each of which would otherwise cost a session:
#   * the app's container UUID changes on reinstall, so the path is resolved
#     once at start and reported -- a moved log otherwise just looks like
#     "no output", which reads identically to "the feature is broken".
#   * AppLog rotates at 512 KB (~6k lines), reachable in a dense keyboard
#     session. tail -F follows by *name*, so it reopens across a rotation;
#     tail -f would sit on the old inode and go silent.
#   * ssh block-buffers when stdout is not a TTY, exactly as idevicesyslog
#     does. stdbuf -oL is mandatory, not tidiness.
#   * lockdownd/usbmuxd need Fedora's SHA-1 signature ban lifted via
#     OPENSSL_CONF, and the device's sshd is old enough to need ssh-rsa
#     explicitly re-enabled on both host keys and pubkey auth.
set -uo pipefail

RUN="${RUN:-$HOME/legacy-ios9/run}"
LOG_DIR="${LOG_DIR:-$HOME/legacy-ios9/logs}"
mkdir -p "$RUN" "$LOG_DIR"
PIDF="$RUN/keylog.pid"
IPROXY_PIDF="$RUN/keylog-iproxy.pid"
PATHF="$RUN/keylog.path"
CURRENT="$LOG_DIR/applog-latest.log"

SSH_PORT="${SSH_PORT:-2222}"      # local end of the USB tunnel
DEVICE_SSH="${DEVICE_SSH:-2269}"  # sshd on the device (OpenSSH from Cydia)
DEVICE_USER="${DEVICE_USER:-root}"
export OPENSSL_CONF="${OPENSSL_CONF:-$HOME/openssl_legacy.cnf}"
# ssh will not read a piped password; ASKPASS is the only way in without a key.
# Same helper ipad.sh uses, so there is one place to change the credential.
for cand in "$HOME/legacy-ios9/ipad-askpass.sh" "$HOME/.ssh/ipad-askpass"; do
    [ -x "$cand" ] && { export SSH_ASKPASS="$cand"; export SSH_ASKPASS_REQUIRE=force; break; }
done

# Two possible homes, and which one applies depends on how the app was
# installed. Cydia puts it in /Applications, which makes it a *system* app with
# no sandboxed data container, so NSCachesDirectory resolves to
# /var/mobile/Library/Caches. A sideloaded build gets a normal container under
# /var/mobile/Containers/Data/Application/<UUID>. Check the system path first:
# it is the one this repo's .deb produces.
GLOBS='/var/mobile/Library/Caches/Logs/opaline.log
/var/mobile/Containers/Data/Application/*/Library/Caches/Logs/opaline.log'

# The device's sshd predates every modern default: ssh-rsa host keys and
# pubkey types, SHA-1 kex and MACs. This is ipad.sh's option set, verbatim.
SSH_OPTS=(
    -o HostKeyAlgorithms=+ssh-rsa
    -o PubkeyAcceptedAlgorithms=+ssh-rsa
    -o KexAlgorithms=+diffie-hellman-group1-sha1,diffie-hellman-group14-sha1
    -o MACs=+hmac-sha1,hmac-sha1-96
    -o IPQoS=throughput
    -o StrictHostKeyChecking=no
    -o UserKnownHostsFile=/dev/null
    -o LogLevel=ERROR
    -o PreferredAuthentications=password
)

ssh_device() {
    setsid ssh -p "$SSH_PORT" "${SSH_OPTS[@]}" -o ConnectTimeout=10 \
        "$DEVICE_USER@127.0.0.1" "$@" < /dev/null
}

alive() { [ -f "$PIDF" ] && kill -0 "$(cat "$PIDF")" 2>/dev/null; }
iproxy_alive() { [ -f "$IPROXY_PIDF" ] && kill -0 "$(cat "$IPROXY_PIDF")" 2>/dev/null; }

start_iproxy() {
    iproxy_alive && return 0
    pgrep -f "^iproxy $SSH_PORT" >/dev/null && return 0
    iproxy "$SSH_PORT" "$DEVICE_SSH" >>"$LOG_DIR/keylog-iproxy.log" 2>&1 &
    echo $! > "$IPROXY_PIDF"
    sleep 1
}

case "${1:-status}" in
start)
    alive && { echo "already running (pid $(cat "$PIDF")) -> $(readlink -f "$CURRENT")"; exit 0; }
    start_iproxy
    # Resolve the container once, and say which one. A reinstall moves it, and
    # silently tailing a path that no longer exists is the worst failure mode
    # here: it is indistinguishable from the app not logging.
    RESOLVED="$(ssh_device "ls -1 $(echo $GLOBS | tr '\n' ' ') 2>/dev/null | head -1" | tr -d '\r')"
    if [ -z "$RESOLVED" ]; then
        echo "no opaline.log on the device."
        echo "  - is the app installed and has it been launched at least once?"
        echo "  - looked in: /var/mobile/Library/Caches/Logs (system app) and"
        echo "               /var/mobile/Containers/.../Caches/Logs (sandboxed)"
        echo "  - is sshd up?  try: ssh -p $SSH_PORT $DEVICE_USER@127.0.0.1 true"
        exit 1
    fi
    echo "$RESOLVED" > "$PATHF"
    LOG="$LOG_DIR/applog-${2:-$(date +%Y%m%d-%H%M%S)}.log"
    : > "$LOG"; ln -sfn "$LOG" "$CURRENT"
    setsid stdbuf -oL ssh -p "$SSH_PORT" "${SSH_OPTS[@]}" \
        -o ServerAliveInterval=15 \
        "$DEVICE_USER@127.0.0.1" \
        "tail -F -n 200 '$RESOLVED'" >>"$LOG" 2>&1 < /dev/null &
    echo $! > "$PIDF"
    sleep 1
    alive && echo "capturing -> $LOG" || { echo "failed to start; see $LOG"; exit 1; }
    echo "device path: $RESOLVED"
    ;;
stop)
    alive && kill "$(cat "$PIDF")" 2>/dev/null && echo "stopped" || echo "not running"
    rm -f "$PIDF"
    iproxy_alive && kill "$(cat "$IPROXY_PIDF")" 2>/dev/null
    rm -f "$IPROXY_PIDF"
    ;;
status)
    alive && echo "keylog up (pid $(cat "$PIDF"))" || echo "keylog down"
    iproxy_alive && echo "iproxy up" || echo "iproxy down (may be shared with serve-repo)"
    [ -f "$PATHF" ] && echo "device path: $(cat "$PATHF")"
    [ -L "$CURRENT" ] && echo "log: $(readlink -f "$CURRENT") ($(wc -l < "$CURRENT") lines)"
    ;;
watch)
    [ -L "$CURRENT" ] || { echo "nothing captured yet; run: $0 start"; exit 1; }
    tail -F -n 100 "$CURRENT" | grep -aE '\[Keys\]|\[Player\]'
    ;;
keys)
    [ -L "$CURRENT" ] || { echo "nothing captured yet; run: $0 start"; exit 1; }
    grep -aE '\[Keys\]' "$CURRENT"
    ;;
raw)
    [ -L "$CURRENT" ] || { echo "nothing captured yet; run: $0 start"; exit 1; }
    tail -n "${2:-50}" "$CURRENT"
    ;;
*)
    sed -n '2,12p' "$0"
    ;;
esac

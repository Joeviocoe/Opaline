#!/usr/bin/env bash
# Device syslog capture over USB, in one command.
#
#   ./devlog.sh start [name]   begin capture, detached
#   ./devlog.sh stop
#   ./devlog.sh status
#   ./devlog.sh watch          follow the filtered stream live
#   ./devlog.sh app            what our app did: launch, dyld, amfid, signals
#   ./devlog.sh crash          crash reports newer than the capture
#   ./devlog.sh raw [n]        last n raw lines (default 50)
#
# Three things this exists to get right, each of which cost a debugging round:
#   * idevicesyslog BLOCK-buffers when stdout is not a TTY, so a naive
#     background capture writes nothing at all until 4 KB accumulates.
#     stdbuf -oL is mandatory, not tidiness.
#   * lockdownd needs Fedora's SHA-1 signature ban lifted, via OPENSSL_CONF.
#   * kills go by recorded PID; `pkill -f` matches its own command line.
set -uo pipefail
RUN="${RUN:-$HOME/legacy-ios9/run}"
LOG_DIR="${LOG_DIR:-$HOME/legacy-ios9/logs}"
mkdir -p "$RUN" "$LOG_DIR"
PIDF="$RUN/devlog.pid"; CURRENT="$LOG_DIR/syslog-latest.log"
export OPENSSL_CONF="${OPENSSL_CONF:-$HOME/openssl_legacy.cnf}"

# Our app, plus everything that explains a launch that does not happen.
APP_RE="${APP_RE:-Gate|Opaline|org\.alcapwn|com\.verback}"
SIG_RE='dyld|amfid|Library not loaded|no such file|code signature|SIGSEGV|SIGTRAP|SIGILL|Abort trap|jetsam|Sandbox: .*deny'
# Chatter this device produces constantly and which never concerns us.
NOISE_RE='ContactsCoreSpotlightExtension|corespotlight|AggregateDictionary|MobileAddressBook'

alive() { [ -f "$PIDF" ] && kill -0 "$(cat "$PIDF")" 2>/dev/null; }
filter() { grep -aE "$APP_RE|$SIG_RE" | grep -avE "$NOISE_RE"; }

case "${1:-status}" in
start)
    alive && { echo "already running (pid $(cat "$PIDF")) -> $(readlink -f "$CURRENT")"; exit 0; }
    LOG="$LOG_DIR/syslog-${2:-$(date +%Y%m%d-%H%M%S)}.log"
    : > "$LOG"; ln -sfn "$LOG" "$CURRENT"
    setsid env OPENSSL_CONF="$OPENSSL_CONF" stdbuf -oL idevicesyslog >>"$LOG" 2>&1 &
    echo $! > "$PIDF"
    for _ in $(seq 20); do [ -s "$LOG" ] && break; sleep 0.5; done
    if [ -s "$LOG" ]; then
        echo "capturing -> $LOG"
        head -1 "$LOG"
    else
        echo "started (pid $(cat "$PIDF")) but nothing captured in 10s --"
        echo "is the iPad connected and unlocked?  idevice_id -l"
    fi ;;
stop)
    [ -f "$PIDF" ] && kill "$(cat "$PIDF")" 2>/dev/null
    rm -f "$PIDF"
    echo "stopped ($(wc -l < "$CURRENT" 2>/dev/null || echo 0) lines in $(readlink -f "$CURRENT" 2>/dev/null))" ;;
status)
    if alive; then echo "up (pid $(cat "$PIDF")), $(wc -l < "$CURRENT") lines -> $(readlink -f "$CURRENT")"
    else echo "not running"; fi ;;
watch)  tail -f "$CURRENT" | filter ;;
app)    filter < "$CURRENT" | tail -"${2:-40}" ;;
crash)
    "$HOME/legacy-ios9/ipad.sh" run \
        'ls -lt /var/mobile/Library/Logs/CrashReporter/*.ips 2>/dev/null | head -5' ;;
raw)    tail -"${2:-50}" "$CURRENT" ;;
*)      sed -n '2,12p' "$0"; exit 2 ;;
esac

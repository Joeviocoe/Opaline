#!/usr/bin/env bash
# Serve the Cydia repo to the iPad over the USB reverse tunnel, detached.
#
# Cydia source URL:  http://127.0.0.1:8080/
#
# Both the HTTP server and the SSH reverse forward are detached and tracked by
# PID file, so they survive the shell that started them.  Kills are by recorded
# PID, never `pkill -f` (which matches its own command line).
#
#   ./serve-repo.sh start | stop | status
set -uo pipefail
REPO_DIR="${REPO_DIR:-$HOME/legacy-ios9/repo}"
RUN="${RUN:-$HOME/legacy-ios9/run}"
HTTP_PORT=8080; SSH_PORT=2222; DEVICE_SSH=2269
mkdir -p "$RUN"
export OPENSSL_CONF="$HOME/openssl_legacy.cnf"
export SSH_ASKPASS="$HOME/.ssh/ipad-askpass" SSH_ASKPASS_REQUIRE=force

kill_pidfile() { [ -f "$1" ] && { kill "$(cat "$1")" 2>/dev/null; rm -f "$1"; }; }
alive() { [ -f "$1" ] && kill -0 "$(cat "$1")" 2>/dev/null; }

case "${1:-start}" in
stop)
    kill_pidfile "$RUN/httpd.pid"; kill_pidfile "$RUN/tunnel.pid"
    echo "stopped"; exit 0 ;;
status)
    alive "$RUN/httpd.pid"  && echo "httpd  up (pid $(cat "$RUN/httpd.pid"))"  || echo "httpd  down"
    alive "$RUN/tunnel.pid" && echo "tunnel up (pid $(cat "$RUN/tunnel.pid"))" || echo "tunnel down"
    pgrep -f '^iproxy 2222' >/dev/null && echo "iproxy up" || echo "iproxy down"
    exit 0 ;;
esac

kill_pidfile "$RUN/httpd.pid"; kill_pidfile "$RUN/tunnel.pid"; sleep 1

echo "== http server on 127.0.0.1:$HTTP_PORT  ($REPO_DIR)"
cd "$REPO_DIR" || exit 1
setsid nohup python3 -m http.server "$HTTP_PORT" --bind 127.0.0.1 \
    >"$RUN/httpd.log" 2>&1 </dev/null &
echo $! > "$RUN/httpd.pid"; sleep 2
curl -sf "http://127.0.0.1:$HTTP_PORT/Packages" >/dev/null \
    && echo "   local fetch OK" || { echo "   FAILED"; exit 1; }

echo "== iproxy $SSH_PORT -> device:$DEVICE_SSH"
pgrep -f "^iproxy $SSH_PORT" >/dev/null || {
    setsid nohup iproxy "$SSH_PORT" "$DEVICE_SSH" >"$RUN/iproxy.log" 2>&1 </dev/null &
    sleep 3; }
pgrep -f "^iproxy $SSH_PORT" >/dev/null && echo "   up" || echo "   FAILED"

echo "== reverse tunnel  device:$HTTP_PORT -> here"
setsid nohup ssh -p "$SSH_PORT" -N -R "$HTTP_PORT:127.0.0.1:$HTTP_PORT" \
  -o HostKeyAlgorithms=+ssh-rsa -o PubkeyAcceptedAlgorithms=+ssh-rsa \
  -o KexAlgorithms=+diffie-hellman-group1-sha1,diffie-hellman-group14-sha1 \
  -o MACs=+hmac-sha1,hmac-sha1-96 -o IPQoS=throughput \
  -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
  -o LogLevel=ERROR -o ExitOnForwardFailure=yes -o ServerAliveInterval=30 \
  root@localhost >"$RUN/tunnel.log" 2>&1 </dev/null &
echo $! > "$RUN/tunnel.pid"; sleep 6
alive "$RUN/tunnel.pid" && echo "   up (pid $(cat "$RUN/tunnel.pid"))" \
    || { echo "   FAILED:"; cat "$RUN/tunnel.log"; exit 1; }

echo
echo "Cydia source:  http://127.0.0.1:8080/"

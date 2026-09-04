#!/usr/bin/env bash
# Verify the LIVE Pages repo the way Cydia will see it.
#   ./verify-pages.sh [base-url]
set -uo pipefail
BASE="${1:-https://joeviocoe.github.io/Opaline}"
BASE="${BASE%/}"
ok=0; bad=0
chk() {
    local code; code=$(curl -sL -o /dev/null -w '%{http_code}' --max-time 25 "$1")
    if [ "$code" = "200" ]; then echo "  OK   $code  $1"; ok=$((ok+1))
    else echo "  FAIL $code  $1"; bad=$((bad+1)); fi
}
echo "=== index files ==="
for f in Release Packages Packages.bz2 Packages.gz CydiaIcon.png index.html; do
    chk "$BASE/$f"
done

echo
echo "=== live Packages stanza ==="
P=$(curl -sL --max-time 25 "$BASE/Packages")
if [ -z "$P" ]; then
    echo "  FAIL: Packages is empty -- Pages may still be building (wait ~1 min)"
    bad=$((bad+1))
else
    printf '%s\n' "$P" | grep -E '^(Package|Name|Version|Section|Filename|Size):' | sed 's/^/  /'
    printf '%s\n' "$P" | grep -q '^Section: Multimedia$' \
        && echo "  OK   Section: Multimedia" || { echo "  FAIL Section wrong"; bad=$((bad+1)); }
fi

echo
echo "=== the deb itself, resolved the way APT resolves Filename ==="
FN=$(printf '%s\n' "$P" | sed -n 's#^Filename: \./\?##p' | head -1)
if [ -n "$FN" ]; then
    URL="$BASE/$FN"
    SIZE=$(curl -sIL --max-time 30 "$URL" | awk 'BEGIN{IGNORECASE=1}/^content-length:/{v=$2}END{print v+0}')
    EXP=$(printf '%s\n' "$P" | sed -n 's/^Size: //p' | head -1)
    echo "  url    $URL"
    echo "  served $SIZE bytes / index says $EXP"
    [ "$SIZE" = "$EXP" ] && { echo "  OK   sizes match"; ok=$((ok+1)); } \
        || { echo "  FAIL size mismatch -- Cydia will reject the download"; bad=$((bad+1)); }
else
    echo "  FAIL no Filename field"; bad=$((bad+1))
fi

echo
echo "=== $ok ok, $bad failed ==="
[ "$bad" -eq 0 ] && echo "Add in Cydia:  $BASE/" || echo "Not ready yet."
exit $([ "$bad" -eq 0 ] && echo 0 || echo 1)

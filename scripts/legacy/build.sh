#!/usr/bin/env bash
# Build Opaline for armv7 / iOS 9.3.5 on Linux.
#
# Logging is the point: a full compile of 376 Swift files on this toolchain is
# slow, so everything is timestamped and streamed to a log you can watch from
# another terminal or over SSH:
#
#     tail -f ~/legacy-ios9/logs/build-latest.log
#
# Every phase is banner-delimited and timed, every file is logged with its
# index and duration, and a failing file dumps its compiler output inline and
# leaves the full stderr in the per-file log named on the failure line.
#
#   ./build.sh --dry-run    show the plan without a toolchain (works today)
#   ./build.sh              full build
#   ./build.sh --sources    print the resolved source list and exit
#
# Env: SWIFTC, SDK, TARGET, MODE=perfile|wmo, JOBS, OPT
set -uo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
TOOLS="${LEGACY_TOOLS:-$HOME/legacy-ios9/toolchain}"
LOG_DIR="${LOG_DIR:-$HOME/legacy-ios9/logs}"
BUILD="${BUILD:-$HOME/legacy-ios9/build}"
mkdir -p "$LOG_DIR" "$BUILD/obj" "$BUILD/logs"

STAMP="$(date +%Y%m%d-%H%M%S)"
LOG="$LOG_DIR/build-$STAMP.log"
ln -sfn "$LOG" "$LOG_DIR/build-latest.log"

SWIFTC="${SWIFTC:-$REPO/scripts/legacy/darling-swiftc}"
SDK="${SDK:-$TOOLS/xc12/Xcode.app/Contents/Developer/Platforms/iPhoneOS.platform/Developer/SDKs/iPhoneOS14.5.sdk}"
TARGET="${TARGET:-armv7-apple-ios9.3}"
MODE="${MODE:-perfile}"
JOBS="${JOBS:-$(nproc)}"
OPT="${OPT:--Osize}"
MODULE=Opaline

DRY=0; SOURCES_ONLY=0
for a in "$@"; do
    case "$a" in
        --dry-run) DRY=1 ;;
        --sources) SOURCES_ONLY=1 ;;
        *) echo "unknown option: $a" >&2; exit 2 ;;
    esac
done

# Unbuffered tee so `tail -f` sees output as it happens, not in 4 KB gulps.
exec > >(stdbuf -oL -eL tee -a "$LOG") 2>&1

T0=$SECONDS
PHASE_T=$SECONDS
ts()   { date +%H:%M:%S; }
log()  { printf '[%s] %s\n' "$(ts)" "$*"; }
phase() {
    local prev=$((SECONDS - PHASE_T))
    [ "${IN_PHASE:-}" ] && printf '[%s] ---- %s finished in %ds\n' "$(ts)" "$IN_PHASE" "$prev"
    IN_PHASE="$1"; PHASE_T=$SECONDS
    printf '\n[%s] ==== %s\n' "$(ts)" "$1"
}
die()  { printf '\n[%s] !!!! FAILED: %s\n' "$(ts)" "$*"; printf '[%s] log: %s\n' "$(ts)" "$LOG"; exit 1; }

# ------------------------------------------------------------------ sources
EXCL="$REPO/scripts/legacy/excluded-sources.txt"
mapfile -t EXCLUDED < <(grep -vE '^\s*(#|$)' "$EXCL")

missing=0
for e in "${EXCLUDED[@]}"; do
    [ -f "$REPO/$e" ] || { echo "  MISSING excluded path: $e"; missing=1; }
done

mapfile -t ALL < <(cd "$REPO" && find Opaline OpalineOpenIn -name '*.swift' | sort)
SOURCES=()
for f in "${ALL[@]}"; do
    skip=0
    for e in "${EXCLUDED[@]}"; do [ "$f" = "$e" ] && { skip=1; break; }; done
    [ $skip -eq 0 ] && SOURCES+=("$REPO/$f")
done

# Assets.xcassets cannot be compiled on Linux (actool is macOS-only), so the
# catalog is flattened into loose PNGs at build time and its template-rendering
# names are emitted as a generated Swift manifest that LegacyAssets consults.
# Nothing is copied into the repo, so upstream icon changes are picked up free.
GENERATED="$BUILD/generated"
STAGING="$BUILD/staging/Opaline.app"
mkdir -p "$GENERATED" "$STAGING"
MANIFEST="$GENERATED/LegacyAssetManifest.swift"
SOURCES+=("$MANIFEST")

if [ "$SOURCES_ONLY" -eq 1 ]; then
    printf '%s\n' "${SOURCES[@]}"
    exit 0
fi

phase "preflight"
log "repo      $REPO"
log "branch    $(git -C "$REPO" branch --show-current)  ($(git -C "$REPO" rev-parse --short HEAD))"
log "target    $TARGET"
log "mode      $MODE   opt $OPT   jobs $JOBS"
log "swiftc    $SWIFTC $([ -x "$SWIFTC" ] && echo '(present)' || echo '*** MISSING ***')"
log "sdk       $SDK $([ -d "$SDK" ] && echo '(present)' || echo '*** MISSING ***')"
log "build dir $BUILD"
log "log       $LOG   (tail -f $LOG_DIR/build-latest.log)"
log "sources   ${#ALL[@]} found, ${#EXCLUDED[@]} excluded, ${#SOURCES[@]} to compile"
[ $missing -eq 1 ] && die "excluded-sources.txt references paths that no longer exist -- upstream moved something"

if [ "$DRY" -eq 1 ]; then
    phase "dry run"
    log "would compile ${#SOURCES[@]} files, then link, bundle, ldid-sign and package"
    log "first 5 sources:"
    printf '           %s\n' "${SOURCES[@]:0:5}" | sed "s|$REPO/||"
    log "excluded:"
    printf '           %s\n' "${EXCLUDED[@]}"
    phase "done"
    log "total $((SECONDS - T0))s"
    exit 0
fi

phase "resources"
python3 "$REPO/scripts/legacy/flatten-assets.py" \
    --catalog "$REPO/Opaline/Assets.xcassets" \
    --out "$STAGING" --manifest "$MANIFEST" || die "flattening Assets.xcassets"
log "localisations"
for lproj in "$REPO"/Opaline/*.lproj; do
    [ -d "$lproj" ] || continue
    cp -R "$lproj" "$STAGING/" && printf '[%s]    %s\n' "$(ts)" "$(basename "$lproj")"
done

[ -x "$SWIFTC" ] || die "no Swift compiler at $SWIFTC (run setup-env.sh --tools, and extract Xcode 12.5.1)"
[ -d "$SDK" ]    || die "no iOS SDK at $SDK (extract Xcode 12.5.1)"

# ------------------------------------------------------------------ compile
phase "compile (${#SOURCES[@]} files, mode=$MODE)"
# -D LEGACY_IOS9 is load-bearing: the compat shims and LegacyAssets' template
# -rendering restoration are all behind it, and without it they compile away to
# nothing silently.  -enable-objc-interop is NOT passed -- it is frontend-only in
# Swift 5.4 and the driver rejects it; interop is on by default for Darwin.
COMMON=(-target "$TARGET" -sdk "$SDK" -module-name "$MODULE" "$OPT"
        -swift-version 5 -D LEGACY_IOS9)

if [ "$MODE" = "wmo" ]; then
    log "whole-module: one frontend process over all ${#SOURCES[@]} files"
    log "if this hangs or OOMs, re-run with MODE=perfile"
    "$SWIFTC" -c -wmo "${COMMON[@]}" "${SOURCES[@]}" -o "$BUILD/obj/$MODULE.o" \
        || die "whole-module compile"
    OBJECTS=("$BUILD/obj/$MODULE.o")
else
    n=0; total=${#SOURCES[@]}; OBJECTS=()
    for f in "${SOURCES[@]}"; do
        n=$((n+1))
        rel="${f#"$REPO"/}"
        obj="$BUILD/obj/$(echo "$rel" | tr '/' '_' | sed 's/\.swift$/.o/')"
        flog="$BUILD/logs/$(echo "$rel" | tr '/' '_').log"
        OBJECTS+=("$obj")
        if [ -f "$obj" ] && [ "$obj" -nt "$f" ]; then
            printf '[%s] [%3d/%d] cached  %s\n' "$(ts)" "$n" "$total" "$rel"
            continue
        fi
        s=$SECONDS
        if "$SWIFTC" -c -primary-file "$f" "${SOURCES[@]}" "${COMMON[@]}" \
                -o "$obj" >"$flog" 2>&1; then
            printf '[%s] [%3d/%d] ok %4ds %s\n' "$(ts)" "$n" "$total" "$((SECONDS-s))" "$rel"
        else
            printf '[%s] [%3d/%d] FAIL     %s\n' "$(ts)" "$n" "$total" "$rel"
            echo "--- first 40 lines of compiler output ---"
            head -40 "$flog"
            echo "--- full output: $flog ---"
            die "compiling $rel"
        fi
    done
fi

# ------------------------------------------------------------------ link
phase "link"
log "linking ${#OBJECTS[@]} object(s)"
"$SWIFTC" "${COMMON[@]}" "${OBJECTS[@]}" -o "$BUILD/$MODULE" \
    || die "link"
log "binary: $BUILD/$MODULE"
command -v lipo >/dev/null && lipo -info "$BUILD/$MODULE"

phase "done"
log "total $((SECONDS - T0))s"
log "full log: $LOG"

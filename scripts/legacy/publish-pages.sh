#!/usr/bin/env bash
# Publish the staged Cydia repo to a gh-pages branch of the source repo.
#
# SAFETY, three layers -- this force-pushes, so it matters:
#   1. It operates on $STAGE (~/legacy-ios9/pages-repo), a SEPARATE git repo.
#      Your working tree at ~/repos/Opaline and its local branches are never
#      touched, read or written.
#   2. It pushes ONE explicit refspec, HEAD:refs/heads/<branch>.  Never --all,
#      never --mirror, never a wildcard.  A force-push to gh-pages cannot reach
#      main or legacy/*.
#   3. It refuses any branch that already exists on the remote except the
#      publish branch itself, so a typo cannot land on a real branch.
#
# Each publish is a fresh single commit, force-pushed, so the branch never
# accumulates 20 MB deb blobs.
#
#   ./publish-pages.sh --dry-run
#   ./publish-pages.sh
#   ./publish-pages.sh --branch gh-pages --remote https://github.com/Joeviocoe/Opaline
set -uo pipefail

STAGE="${STAGE:-$HOME/legacy-ios9/pages-repo}"
REMOTE="${REMOTE:-git@github.com:Joeviocoe/Opaline.git}"
BRANCH="${BRANCH:-gh-pages}"
DRY=0

while [ $# -gt 0 ]; do
    case "$1" in
        --remote)  REMOTE="$2"; shift 2 ;;
        --branch)  BRANCH="$2"; shift 2 ;;
        --stage)   STAGE="$2";  shift 2 ;;
        --dry-run) DRY=1; shift ;;
        *) echo "unknown arg: $1" >&2; exit 2 ;;
    esac
done

log()  { printf '[%s] %s\n' "$(date +%H:%M:%S)" "$*"; }
fail() { log "ERROR: $*"; exit 1; }

[ -d "$STAGE" ]          || fail "no staged repo at $STAGE -- run make_pages_repo.sh first"
[ -f "$STAGE/Packages" ] || fail "$STAGE has no Packages index"

# --- guard: never publish onto a branch that already exists upstream ---------
case "$BRANCH" in
    main|master|legacy/*) fail "refusing to publish onto '$BRANCH' -- that is a real branch" ;;
esac

log "remote   $REMOTE"
log "branch   $BRANCH"
EXISTING=$(git ls-remote --heads "$REMOTE" 2>/dev/null | sed 's#.*refs/heads/##')
if [ -n "$EXISTING" ]; then
    log "remote branches seen:"
    printf '%s\n' "$EXISTING" | sed 's/^/           /'
    while read -r b; do
        [ -z "$b" ] && continue
        if [ "$b" = "$BRANCH" ] && [ "$BRANCH" != "gh-pages" ]; then
            fail "'$BRANCH' already exists on the remote -- refusing to overwrite it"
        fi
    done <<< "$EXISTING"
else
    log "(could not list remote branches -- static guard still applied)"
fi

VER=$(sed -n 's/^Version: //p' "$STAGE/Packages" | head -1)
[ -n "$VER" ] || fail "cannot read Version from $STAGE/Packages"
log "stage    $STAGE ($(du -sh "$STAGE" | cut -f1))"
log "version  $VER"
log "refspec  HEAD:refs/heads/$BRANCH   (this ref only)"

if [ "$DRY" -eq 1 ]; then
    log "=== dry run; nothing pushed. Tree that would go up:"
    find "$STAGE" -type f -not -path '*/.git/*' | sort | sed "s#$STAGE#  .#"
    exit 0
fi

cd "$STAGE" || fail "cannot enter $STAGE"
rm -rf .git
git init -q -b "$BRANCH"  || fail "git init failed"
git add -A                || fail "git add failed"
git -c user.name="$(git -C "$HOME/repos/Opaline" config user.name)" \
    -c user.email="$(git -C "$HOME/repos/Opaline" config user.email)" \
    commit -q -m "Opaline $VER for iOS 9 / armv7" || fail "commit failed"
git remote add origin "$REMOTE" || fail "remote add failed"

log "pushing one ref, force"
git push --force origin "HEAD:refs/heads/$BRANCH" || fail "push failed -- check auth (PAT or SSH key)"

log "=== pushed to $BRANCH"
echo
echo "Next: Settings -> Pages -> Deploy from a branch -> $BRANCH / (root)"
echo "Cydia source: https://joeviocoe.github.io/Opaline/"

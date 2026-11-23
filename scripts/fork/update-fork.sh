#!/usr/bin/env bash
# Brings Rob's Phosphor fork (rdysell/phosphor-fork) up to date with upstream (fillinthe/phosphor) and rebuilds the
# `rob` branch: upstream main with every fix branch listed in fork-fixes.txt merged on top. Pulling an update never
# loses a fix, because no fix lives on `main`; they're merged in again after each update.
#
#   main         = upstream main exactly (never commit here; this script moves it forward)
#   <fix branch> = one fix each, branched from upstream main; each one is also an upstream pull request
#   fork-tools   = this script, FORK.md and fork-fixes.txt (the list of fix branches)
#   rob          = upstream main + fork-tools + each listed fix: what we build and run
#
# Usage, from any clone of Phosphor (your checkout is left alone; the work happens in a temporary worktree):
#   scripts/fork/update-fork.sh          # dry run: says what it would do, pushes nothing
#   scripts/fork/update-fork.sh --push   # also moves the fork's main and force-pushes the rebuilt rob
#   scripts/fork/update-fork.sh --push --force-main   # upstream rewrote its history: main follows it anyway
#
# It stops, and pushes nothing, when a fix no longer merges cleanly (rebase that fix branch onto upstream main and
# run it again) or when the fork's main has commits upstream doesn't (upstream rewrote history, or someone committed
# on the fork's main).
set -euo pipefail

UPSTREAM_URL="${UPSTREAM_URL:-https://github.com/fillinthe/phosphor.git}"
FORK_URL="${FORK_URL:-https://github.com/rdysell/phosphor-fork.git}"
NS="refs/fork-sync"
PUSH=0
FORCE_MAIN=0
for arg in "$@"; do
    case "$arg" in
        --push) PUSH=1 ;;
        --force-main) FORCE_MAIN=1 ;;
        -h | --help) sed -n '2,20p' "$0"; exit 0 ;;
        *) echo "unknown option: $arg" >&2; exit 2 ;;
    esac
done

git rev-parse --git-dir >/dev/null
say() { printf '%s\n' "$*"; }

say "Fetching upstream main and the fork's branches…"
git fetch --quiet --no-tags "$UPSTREAM_URL" "+refs/heads/main:$NS/upstream/main"
git for-each-ref --format='%(refname)' "$NS/fork/" | while read -r r; do git update-ref -d "$r"; done
git fetch --quiet --no-tags "$FORK_URL" "+refs/heads/*:$NS/fork/*"
upstream=$(git rev-parse "$NS/upstream/main")
fork_main=$(git rev-parse -q --verify "$NS/fork/main" || true)
old_rob=$(git rev-parse -q --verify "$NS/fork/rob" || true)
say "upstream main: $(git log -1 --format='%h %s' "$upstream")"

# 1. The fork's main follows upstream (fast-forward only, unless --force-main).
main_push=""
if [ "$fork_main" = "$upstream" ]; then
    say "fork main: already at upstream"
elif [ -z "$fork_main" ] || git merge-base --is-ancestor "$fork_main" "$upstream"; then
    say "fork main: moves forward to upstream ($(git rev-list --count "${fork_main:+$fork_main..}$upstream") new commits)"
    main_push="$upstream:refs/heads/main"
elif [ "$FORCE_MAIN" = 1 ]; then
    say "fork main: has commits upstream doesn't; --force-main: it follows upstream anyway"
    main_push="+$upstream:refs/heads/main"
else
    say "STOP: the fork's main has commits upstream doesn't (upstream rewrote its history, or someone committed on"
    say "      the fork's main). Fixes belong on their own branches. Check, then run again with --force-main."
    exit 1
fi

# 2. The list of fixes, from the fork-tools branch (this checkout's copy when fork-tools isn't pushed yet).
if git rev-parse -q --verify "$NS/fork/fork-tools" >/dev/null; then
    list=$(git show "$NS/fork/fork-tools:fork-fixes.txt")
else
    say "(fork-tools isn't on the fork yet: using this checkout's fork-fixes.txt)"
    list=$(cat "$(git rev-parse --show-toplevel)/fork-fixes.txt")
fi
branches=$(printf '%s\n' "$list" | sed -e 's/#.*//' -e 's/[[:space:]]//g' | grep -v '^$' || true)

# 3. Rebuild rob in a throwaway worktree: upstream main, then each fix merged in turn.
tmp=$(mktemp -d "${TMPDIR:-/tmp}/phosphor-rob.XXXXXX")
cleanup() { git worktree remove --force "$tmp" >/dev/null 2>&1 || true; rm -rf "$tmp"; }
trap cleanup EXIT
git worktree add --quiet --detach "$tmp" "$upstream"
merged=() upstreamed=() missing=()
for b in $branches; do
    ref="$NS/fork/$b"
    if ! git rev-parse -q --verify "$ref" >/dev/null; then
        missing+=("$b")
        say "  $b: not on the fork (push it first), left out"
        continue
    fi
    if git merge-base --is-ancestor "$ref" "$upstream"; then
        upstreamed+=("$b")
        say "  $b: already in upstream main (merged): take it off fork-fixes.txt"
        continue
    fi
    if ! git merge-base "$ref" "$upstream" >/dev/null; then
        say "STOP: $b shares no history with upstream main (it was made before upstream rewrote its history)."
        say "      Rebase it: git rebase --onto $NS/upstream/main <its old base> $b, push it, run again."
        exit 1
    fi
    # Squash-merged upstream: every commit of the fix already has an equal patch upstream.
    # (Counted, not grep -q: with pipefail, grep quitting early would fail the pipe and mark a live fix as merged.)
    if [ "$(git cherry "$upstream" "$ref" | grep -c '^+' || true)" = 0 ]; then
        upstreamed+=("$b")
        say "  $b: its changes are in upstream main already (squash-merged): take it off fork-fixes.txt"
        continue
    fi
    if git -C "$tmp" merge --quiet --no-ff --no-edit -m "rob: merge $b" "$ref" >/dev/null 2>&1; then
        merged+=("$b")
        say "  $b: merged ($(git rev-list --count "$upstream..$ref") commits)"
    else
        say "STOP: $b no longer merges cleanly on upstream main + the fixes before it:"
        git -C "$tmp" diff --name-only --diff-filter=U | sed 's/^/        /'
        say "      Rebase $b onto upstream main (and the fixes it overlaps), push it, run again. Nothing was pushed."
        exit 1
    fi
done
rob=$(git -C "$tmp" rev-parse HEAD)
# Nothing new (same files, and the old rob already has upstream and every fix): keep it rather than push fresh merges.
rob_push="+$rob:refs/heads/rob"
if [ -n "$old_rob" ] && [ "$(git rev-parse "$old_rob^{tree}")" = "$(git rev-parse "$rob^{tree}")" ] && git merge-base --is-ancestor "$upstream" "$old_rob"; then
    same=1
    for b in "${merged[@]:-}"; do
        [ -z "$b" ] || git merge-base --is-ancestor "$NS/fork/$b" "$old_rob" || same=0
    done
    if [ "$same" = 1 ]; then
        rob=$old_rob
        rob_push=""
    fi
fi

say ""
say "rob would be: upstream main + ${#merged[@]} fixes (${merged[*]:-none}) = $(git log -1 --format=%h "$rob")"
[ ${#upstreamed[@]} -gt 0 ] && say "Merged upstream, drop from fork-fixes.txt: ${upstreamed[*]}"
[ ${#missing[@]} -gt 0 ] && say "Listed but not on the fork: ${missing[*]}"
if [ -n "$old_rob" ]; then
    lost=$(git log --format='%h %s' --no-merges "$rob..$old_rob" | grep -v '^$' || true)
    if [ -n "$lost" ]; then
        say "Commits on the old rob that the new one won't have (check none of them is a fix you still want):"
        printf '%s\n' "$lost" | sed 's/^/    /' | head -40
    fi
fi

if [ -z "$main_push" ] && [ -z "$rob_push" ]; then
    say "Nothing to push: the fork's main and rob are up to date."
elif [ "$PUSH" = 1 ]; then
    lease="--force-with-lease=refs/heads/rob:${old_rob}"
    git push "$FORK_URL" $main_push $rob_push "$lease"
    say "Pushed. Build and run the rob branch."
else
    say "Dry run: nothing pushed. Run again with --push to update the fork."
fi

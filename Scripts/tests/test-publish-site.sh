#!/usr/bin/env bash
# Hermetic regression test for Scripts/publish-site.sh.
#
# Usage: ./Scripts/tests/test-publish-site.sh
#
# Builds a throwaway repo in a temp dir (a bare repo as `origin` plus a clone holding a
# copy of the script and a minimal site/), then publishes several times and checks what
# lands on origin's gh-pages. Never touches the real repo or its remote.
set -euo pipefail

script_src="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/publish-site.sh"
[[ -f "$script_src" ]] || { echo "error: no publish script at $script_src" >&2; exit 1; }

tmp="$(mktemp -d "${TMPDIR:-/tmp}/murmur-publish-test.XXXXXX")"
trap 'rm -rf "$tmp"' EXIT

# Reason: ignore the developer's global/system git config (signing, hooks, default
# branch) so the result depends only on what this test sets up.
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1
export TMPDIR="$tmp"    # the script's worktree also lands in the temp dir

origin="$tmp/origin.git"
clone="$tmp/clone"
failures=0

# Prints a failure line and records it, without stopping the remaining checks.
fail() { echo "FAIL: $*"; failures=$((failures + 1)); }

# Runs the copied publish script; reports a failure (with its output) on non-zero exit.
publish() {
    local label="$1"; shift
    local out
    if out="$("$clone/Scripts/publish-site.sh" "$@" 2>&1)"; then
        echo "ok: $label exited 0"
    else
        fail "$label exited non-zero:"
        printf '    %s\n' "$out"
    fi
}

# Asserts origin's gh-pages holds the published layout and the expected index.html.
check_origin() {
    local label="$1" expected_index="$2"
    local files before=$failures
    files="$(git -C "$origin" ls-tree --name-only gh-pages 2>/dev/null)" \
        || { fail "$label: origin has no gh-pages branch"; return; }
    for f in index.html BUILD.md .nojekyll; do
        grep -qxF "$f" <<<"$files" || fail "$label: $f missing on origin gh-pages"
    done
    grep -qxF README.md <<<"$files" && fail "$label: README.md should be renamed to BUILD.md"
    local index
    index="$(git -C "$origin" show gh-pages:index.html)"
    [[ "$index" == "$expected_index" ]] \
        || fail "$label: origin index.html is '$index', expected '$expected_index'"
    (( failures == before )) && echo "ok: $label origin gh-pages content"
    return 0
}

git init -q --bare "$origin"
git init -q -b main "$clone"
git -C "$clone" config user.name "Publish Test"
git -C "$clone" config user.email "publish-test@example.invalid"
git -C "$clone" config commit.gpgsign false
git -C "$clone" remote add origin "$origin"

mkdir -p "$clone/Scripts" "$clone/site"
cp "$script_src" "$clone/Scripts/publish-site.sh"
chmod +x "$clone/Scripts/publish-site.sh"
echo "v1" > "$clone/site/index.html"
echo "site readme" > "$clone/site/README.md"
git -C "$clone" add -A
git -C "$clone" commit -q -m "init"
git -C "$clone" push -q origin main

# 1. First publish into an empty origin; it must leave no worktree or local branch behind.
publish "first run"
check_origin "first run" "v1"
git -C "$clone" show-ref --verify --quiet refs/heads/gh-pages \
    && fail "first run left a local gh-pages branch behind"
[[ "$(git -C "$clone" worktree list | wc -l)" -eq 1 ]] \
    || fail "first run left a git worktree behind"

# 2. A second publish must succeed and ship the changed content.
echo "v2" > "$clone/site/index.html"
publish "second run"
check_origin "second run" "v2"

# 3. A stale local gh-pages that has diverged from origin must not block publishing.
git -C "$clone" branch -f gh-pages main
echo "v3" > "$clone/site/index.html"
publish "run over stale local gh-pages"
check_origin "run over stale local gh-pages" "v3"

if (( failures > 0 )); then
    echo "$failures check(s) failed"
    exit 1
fi
echo "all checks passed"

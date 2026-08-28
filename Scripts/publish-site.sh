#!/usr/bin/env bash
# Publish site/ to the gh-pages branch that GitHub Pages serves.
#
# Usage: ./Scripts/publish-site.sh ["message"]
#
# gh-pages is disposable: it is rebuilt from site/ on every run. Never hand-edit it.
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
site_dir="$repo_root/site"
branch="gh-pages"

[[ -d "$site_dir" ]] || { echo "error: no site/ directory at $site_dir" >&2; exit 1; }

worktree="$(mktemp -d "${TMPDIR:-/tmp}/murmur-pages.XXXXXX")"
rmdir "$worktree"   # git worktree add requires an absent path
cleanup() { git -C "$repo_root" worktree remove --force "$worktree" 2>/dev/null || true; }
trap cleanup EXIT

# Reason: an orphan branch, so the published tree holds only the site and not the
# Swift sources, vendored whisper.cpp build or model files from main.
git -C "$repo_root" worktree add --orphan -q "$worktree"
cd "$worktree"

cp -R "$site_dir/." .
# This readme describes the source folder; index.html is the page itself.
mv README.md BUILD.md
: > .nojekyll       # static output: skip Jekyll processing entirely

git add -A
git -c user.name="$(git -C "$repo_root" config user.name)" \
    -c user.email="$(git -C "$repo_root" config user.email)" \
    commit -q -m "${1:-chore(site): publish project page}"

echo "publishing $(git rev-parse --short HEAD) to $branch ..."
git push -q --force "origin" "$branch"
echo "done. Pages rebuilds on this push."

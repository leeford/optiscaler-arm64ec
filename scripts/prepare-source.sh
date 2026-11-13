#!/bin/bash
# Check out mainline OptiScaler and apply this repo's patch series on top.
#
# The patches apply exactly on the commit in patches/BASE; the result is then
# rebased onto UPSTREAM_REF. git am -3 alone cannot do this: a patch's index lines
# name blobs from the old base plus earlier patches, which do not exist on a newer
# base, so any file touched by two patches and changed upstream fails with no merge.
#
#   scripts/prepare-source.sh [SRC_DIR] [UPSTREAM_REF]
#
#   SRC_DIR       where the checkout lives (default: ./src)
#   UPSTREAM_REF  branch, tag or commit of optiscaler/OptiScaler (default: master)
#
# Exit codes: 0 applied cleanly, 3 a patch no longer applies. On 3, the failing
# patch and the conflicting files are written to $SRC_DIR.conflicts.md and the
# checkout is left at the last patch that applied, for inspection.
set -euo pipefail
here=$(cd "$(dirname "$0")/.." && pwd)

# Upstream edits OptiScaler.ini almost daily, so patching it means a conflict most
# weeks. Its changes for this build go in scripts/configure-ini.py instead.
if ini_patches=$(grep -l '^diff --git a/OptiScaler.ini ' "$here"/patches/*.patch); then
  echo "These patches change OptiScaler.ini; move the change to scripts/configure-ini.py:" >&2
  echo "$ini_patches" >&2
  exit 1
fi
SRC=${1:-$PWD/src}
REF=${2:-master}
UPSTREAM=${UPSTREAM_URL:-https://github.com/optiscaler/OptiScaler}
report="$SRC.conflicts.md"
rm -f "$report"

git_() { git -C "$SRC" -c user.name="optiscaler-arm64ec" \
  -c user.email="optiscaler-arm64ec@users.noreply.github.com" "$@"; }

if [ ! -d "$SRC/.git" ]; then
  git init -q "$SRC"
  git_ remote add upstream "$UPSTREAM"
fi
# Enough history for 3-way merges of the patches.
git_ fetch -q --depth 200 upstream "$REF"
base=$(git_ rev-parse FETCH_HEAD)
series_base=$(cat "$here/patches/BASE")
git_ fetch -q --depth 200 upstream "$series_base"
git_ am --abort >/dev/null 2>&1 || true
git_ rebase --abort >/dev/null 2>&1 || true
git_ checkout -q -f -B arm64ec "$series_base"
git_ clean -q -fdx -e '/external/'
git_ update-ref refs/upstream-base "$base"   # read by package.sh and refresh-patches.sh
echo "upstream: $base ($(git_ log -1 --format=%cs "$base"))"
echo "patches written on: $series_base"

echo "== patch series"
git_ am -q --keep-cr "$here"/patches/*.patch
if ! git_ rebase -q --onto "$base" "$series_base" arm64ec; then
  failing=$(git_ log -1 --format=%s REBASE_HEAD 2>/dev/null || true)
  files=$(git_ diff --name-only --diff-filter=U || true)
  {
    echo "Upstream commit: \`$base\`"
    echo
    echo "Failing patch: **${failing:-unknown}**"
    echo
    echo "Conflicting files:"
    if [ -n "$files" ]; then printf -- '- `%s`\n' $files; else echo "- (none listed; see the workflow log)"; fi
  } > "$report"
  cat "$report"
  exit 3
fi
echo "applied $(ls "$here"/patches/*.patch | wc -l) patches"

echo "== submodules"
GIT_LFS_SKIP_SMUDGE=1 git_ submodule -q sync
GIT_LFS_SKIP_SMUDGE=1 git_ submodule -q update --init --depth 1 --jobs 4

# unordered_dense uses _umul128, which ARM64EC does not have. The submodule pin
# cannot carry the change, so patch the checkout; skip if already applied.
ud="$SRC/external/unordered_dense"
p="$here/patches/submodules/unordered_dense-arm64ec.patch"
if git -C "$ud" apply --check --reverse "$p" 2>/dev/null; then
  echo "unordered_dense: already patched"
elif ! git -C "$ud" apply "$p"; then
  {
    echo "Upstream commit: \`$base\`"
    echo
    echo "Failing patch: **submodules/unordered_dense-arm64ec.patch** (the unordered_dense submodule was updated)"
    echo
    echo "Conflicting files:"
    echo '- `external/unordered_dense/include/ankerl/unordered_dense.h`'
  } > "$report"
  cat "$report"
  exit 3
fi
echo "source ready: $SRC"

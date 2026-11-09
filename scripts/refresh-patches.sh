#!/bin/bash
# Rebase the patch series onto current mainline when it stops applying.
#
#   scripts/refresh-patches.sh           # apply onto upstream master in ./src
#   # ... the rebase stops at a conflict: fix the files in ./src, then
#   git -C src add -A && git -C src rebase --continue  # repeat as needed
#   scripts/refresh-patches.sh --export  # write the rebased series to patches/
#
# Commit the changed patches/ and push; the workflow builds and releases.
set -euo pipefail
here=$(cd "$(dirname "$0")/.." && pwd)
SRC=${SRC:-$PWD/src}

if [ "${1:-}" = --export ]; then
  if [ -d "$SRC/.git/rebase-apply" ] || [ -d "$SRC/.git/rebase-merge" ]; then
    echo "a rebase is still in progress in $SRC; finish it first" >&2
    exit 1
  fi
  base=$(git -C "$SRC" rev-parse refs/upstream-base)
  rm -f "$here"/patches/*.patch
  git -C "$SRC" format-patch -q --zero-commit --no-signature -o "$here/patches" "$base..HEAD"
  echo "$base" > "$here/patches/BASE"
  echo "exported $(ls "$here"/patches/*.patch | wc -l) patches onto upstream ${base:0:7}"
  git -C "$here" status --short patches
  exit 0
fi

if "$here/scripts/prepare-source.sh" "$SRC" "${1:-master}"; then
  echo "The series applies cleanly; nothing to refresh."
else
  echo
  echo "Resolve the conflicts in $SRC, then: git -C $SRC add -A && git -C $SRC rebase --continue"
  echo "When the rebase has finished, run: scripts/refresh-patches.sh --export"
fi

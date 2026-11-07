#!/bin/bash
# Runs Microsoft's fxc.exe (from the Windows SDK, fetched by setup-toolchain.sh)
# under Wine, translating absolute Unix paths in the arguments to Z:\ paths.
set -euo pipefail
: "${FXC_DIR:?set FXC_DIR to the folder holding fxc.exe and d3dcompiler_47.dll}"
export WINEPREFIX="${WINEPREFIX:-$FXC_DIR/wineprefix}"
export WINEDEBUG=-all
# Use the SDK's d3dcompiler_47.dll next to fxc.exe, not Wine's builtin one.
export WINEDLLOVERRIDES="d3dcompiler_47=n;mscoree,mshtml="
args=()
for a in "$@"; do
  # fxc switches also start with "/", so only translate things that look like paths.
  if [[ $a == /*/* && -d $(dirname -- "$a") ]]; then
    a="Z:${a//\//\\}"
  fi
  args+=("$a")
done
# Debian/Ubuntu's wine64 package ships only wine64; the wine launcher is separate.
wine=$(command -v wine || command -v wine64) || { echo "fxc.sh: wine not found" >&2; exit 127; }
exec "$wine" "$FXC_DIR/fxc.exe" "${args[@]}"

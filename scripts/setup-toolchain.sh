#!/bin/bash
# Set up the Linux cross toolchain for the ARM64EC build (Ubuntu 24.04 / Debian).
#
#   - clang-cl, lld-link, llvm-lib/rc/ar   from apt.llvm.org   (LLVM_VERSION)
#   - MSVC CRT + Windows SDK               via xwin            (XWIN_*)
#   - fxc.exe + d3dcompiler_47.dll         from the Windows SDK, run under Wine
#
# Everything lands under $TOOLS (default: ./.tools). Re-running is cheap: steps
# whose output already exists are skipped, so CI can cache $TOOLS.
#
# Running this means accepting the Microsoft Visual Studio / Windows SDK licence
# terms for the downloaded CRT and SDK (xwin --accept-license). They are used to
# build only and are never redistributed in the release package.
set -euo pipefail

LLVM_VERSION=${LLVM_VERSION:-22}
XWIN_VERSION=${XWIN_VERSION:-0.10.0}
XWIN_CRT_VERSION=${XWIN_CRT_VERSION:-14.44.17.14}
XWIN_SDK_VERSION=${XWIN_SDK_VERSION:-10.0.26100}
TOOLS=${TOOLS:-$PWD/.tools}
mkdir -p "$TOOLS"
TOOLS=$(cd "$TOOLS" && pwd)

sudo_() { if [ "$(id -u)" -eq 0 ]; then "$@"; else sudo "$@"; fi; }

# ---------------------------------------------------------------- apt packages
if [ "${SKIP_APT:-0}" != 1 ]; then
  echo "== apt: LLVM $LLVM_VERSION, cmake, ninja, wine, msitools"
  codename=$(. /etc/os-release && echo "$VERSION_CODENAME")
  if ! command -v "clang-cl-$LLVM_VERSION" >/dev/null; then
    curl -fsSL https://apt.llvm.org/llvm-snapshot.gpg.key | sudo_ tee /etc/apt/trusted.gpg.d/apt.llvm.org.asc >/dev/null
    echo "deb https://apt.llvm.org/$codename/ llvm-toolchain-$codename-$LLVM_VERSION main" |
      sudo_ tee /etc/apt/sources.list.d/llvm-$LLVM_VERSION.list >/dev/null
  fi
  sudo_ apt-get update -qq
  DEBIAN_FRONTEND=noninteractive sudo_ apt-get install -y -qq --no-install-recommends \
    "clang-$LLVM_VERSION" "lld-$LLVM_VERSION" "llvm-$LLVM_VERSION" \
    cmake ninja-build msitools wine64 python3 zip unzip git ca-certificates curl >/dev/null
fi
for t in clang-cl lld-link llvm-lib llvm-rc llvm-ar; do
  command -v "$t-$LLVM_VERSION" >/dev/null || { echo "missing $t-$LLVM_VERSION" >&2; exit 1; }
done

# ----------------------------------------------------------------------- xwin
XWIN=$TOOLS/bin/xwin
if [ ! -x "$XWIN" ] || ! "$XWIN" --version | grep -q "$XWIN_VERSION"; then
  echo "== xwin $XWIN_VERSION"
  mkdir -p "$TOOLS/bin"
  url="https://github.com/Jake-Shadle/xwin/releases/download/$XWIN_VERSION/xwin-$XWIN_VERSION-x86_64-unknown-linux-musl.tar.gz"
  if curl -fsSL "$url" | tar -xz -C "$TOOLS/bin" --strip-components=1 "xwin-$XWIN_VERSION-x86_64-unknown-linux-musl/xwin" 2>/dev/null; then
    :
  else
    echo "   release download failed, building with cargo"
    cargo install --locked --version "$XWIN_VERSION" --root "$TOOLS" xwin
  fi
fi

SYSROOT=$TOOLS/sysroot
XWIN_CACHE=$TOOLS/xwin-cache
xwin_() {
  "$XWIN" --accept-license --cache-dir "$XWIN_CACHE" --http-retry 3 \
    --crt-version "$XWIN_CRT_VERSION" --sdk-version "$XWIN_SDK_VERSION" \
    --arch x86_64,aarch64 "$@"
}
if [ ! -d "$SYSROOT/VC/Tools/MSVC/$XWIN_CRT_VERSION" ]; then
  echo "== MSVC CRT $XWIN_CRT_VERSION + Windows SDK $XWIN_SDK_VERSION"
  rm -rf "$SYSROOT"
  xwin_ splat --use-winsysroot-style --preserve-ms-arch-notation --output "$SYSROOT"
  # Keep the manifest (for fxc below) but drop the 1+ GB of unpacked payloads.
  find "$XWIN_CACHE" -mindepth 1 -maxdepth 1 ! -name dl -exec rm -rf {} +
  find "$XWIN_CACHE/dl" -mindepth 1 ! -name '*.vsman' ! -name '*.json' -exec rm -rf {} +
fi
ucrt_dir="$SYSROOT/Windows Kits/10/Lib/$XWIN_SDK_VERSION/ucrt"
if [ ! -f "$ucrt_dir/arm64ec/ucrt.lib" ]; then
  echo "== ARM64EC UCRT import library"
  python3 -I "$(dirname "$0")/make-ucrt-arm64ec.py" "$ucrt_dir/x64/ucrt.lib" "$ucrt_dir/arm64ec/ucrt.lib" "-$LLVM_VERSION"
fi

# ------------------------------------------------------------------------ fxc
FXC_DIR=$TOOLS/fxc
if [ ! -f "$FXC_DIR/fxc.exe" ]; then
  echo "== fxc.exe from the Windows SDK"
  find_manifest() { find "$XWIN_CACHE/dl" -maxdepth 1 -name '*.vsman' 2>/dev/null | head -1; }
  manifest=$(find_manifest)
  [ -n "$manifest" ] || { xwin_ list >/dev/null; manifest=$(find_manifest); }
  work=$(mktemp -d)
  python3 -I - "$manifest" "$XWIN_SDK_VERSION" > "$work/payloads.tsv" <<'PY'
import json, sys
m = json.load(open(sys.argv[1]))
for p in m["packages"]:
    if p["id"].startswith("Win11SDK_" + sys.argv[2]):
        for x in p.get("payloads", []):
            print(x["fileName"].replace("\\", "/") + "\t" + x["url"])
PY
  msi="Installers/Windows SDK for Windows Store Apps Tools-x86_en-us.msi"
  url_of() { awk -F'\t' -v n="$1" '$1==n {print $2; exit}' "$work/payloads.tsv"; }
  curl -fsSL -o "$work/tools.msi" "$(url_of "$msi")"
  for cab in $(msiinfo export "$work/tools.msi" Media | awk -F'\t' 'NR>3 && $4!="" {print $4}'); do
    curl -fsSL -o "$work/$cab" "$(url_of "Installers/$cab")"
  done
  (cd "$work" && msiextract -C "$work/x" tools.msi >/dev/null)
  bin=$(dirname "$(find "$work/x" -path '*/x64/fxc.exe' | head -1)")
  mkdir -p "$FXC_DIR"
  cp "$bin/fxc.exe" "$bin/d3dcompiler_47.dll" "$FXC_DIR/"
  rm -rf "$work"
fi
# First Wine start creates the prefix; do it here so the build log stays quiet.
WINEPREFIX=$FXC_DIR/wineprefix WINEDEBUG=-all WINEDLLOVERRIDES="mscoree,mshtml=" \
  wine "$FXC_DIR/fxc.exe" /? >/dev/null 2>&1 || true

cat > "$TOOLS/env.sh" <<EOF
export XWIN_SYSROOT="$SYSROOT"
export LLVM_SUFFIX="-$LLVM_VERSION"
export FXC_DIR="$FXC_DIR"
export WINEPREFIX="$FXC_DIR/wineprefix"
EOF
echo "== toolchain ready; source $TOOLS/env.sh"

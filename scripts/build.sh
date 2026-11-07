#!/bin/bash
# Build OptiScaler.dll for ARM64EC from a patched checkout.
#
#   source .tools/env.sh            # from scripts/setup-toolchain.sh
#   scripts/build.sh [SRC_DIR] [OUT_DIR]
#
# SRC_DIR defaults to ./src (scripts/prepare-source.sh), OUT_DIR to ./out.
# The DLL ends up at $OUT_DIR/build/OptiScaler.dll.
set -euo pipefail
here=$(cd "$(dirname "$0")/.." && pwd)
SRC=$(cd "${1:-$PWD/src}" && pwd)
OUT=${2:-$PWD/out}
mkdir -p "$OUT"
OUT=$(cd "$OUT" && pwd)
: "${XWIN_SYSROOT:?source .tools/env.sh first}" "${FXC_DIR:?source .tools/env.sh first}"
export LLVM_SUFFIX=${LLVM_SUFFIX:-}

# Pinned dependency sources, built from source with the same toolchain.
DETOURS_URL=https://github.com/microsoft/Detours
DETOURS_REV=${DETOURS_REV:-1dbd4ea}
FREETYPE_URL=https://github.com/freetype/freetype
FREETYPE_TAG=${FREETYPE_TAG:-VER-2-13-3}   # matches external/freetype headers

echo "== prebuilt FidelityFX libraries"
(cd "$here/prebuilt/fsr-arm64ec" && sha256sum --quiet -c SHA256SUMS)

DEPS=$OUT/deps
stamp="$DEPS/.stamp-$DETOURS_REV-$FREETYPE_TAG"
if [ ! -f "$stamp" ]; then
  echo "== Detours $DETOURS_REV, FreeType $FREETYPE_TAG"
  rm -rf "$DEPS" "$OUT/depsrc"
  mkdir -p "$OUT/depsrc"
  git clone -q --filter=blob:none "$DETOURS_URL" "$OUT/depsrc/detours"
  git -C "$OUT/depsrc/detours" checkout -q "$DETOURS_REV"
  git clone -q --depth 1 --branch "$FREETYPE_TAG" "$FREETYPE_URL" "$OUT/depsrc/freetype"
  DEPS_SRC=$OUT/depsrc DEPS_PREFIX=$DEPS DEPS_BUILD=$OUT/depsbuild "$here/scripts/build-deps.sh"
  touch "$stamp"
fi
cp "$here"/prebuilt/fsr-arm64ec/*.lib "$DEPS/lib/"
# Import libraries only (x64 COFF import entries, which ARM64EC links against).
cp "$SRC/OptiScaler/library/vulkan/vulkan-1.lib" "$SRC/OptiScaler/library/d3dx/d3dx11.lib" "$DEPS/lib/"

echo "== include case fixes"
P=$SRC/OptiScaler E=$SRC/external
K=$(ls -d "$XWIN_SYSROOT/Windows Kits/10/Include/"* | tail -1)
python3 -I "$here/scripts/fix-include-case.py" --scan "$P" \
  --include "$P" --include "$P/include" --include "$E/vulkan/include" --include "$E/xess/inc/xess" \
  --include "$E/FidelityFX-SDK/ffx-api/include/ffx_api" --include "$E/nvapi" --include "$E/streamline" \
  --include "$K/um" --include "$K/shared" --include "$K/winrt" --include "$K/ucrt" \
  --libdir "$(ls -d "$XWIN_SYSROOT/Windows Kits/10/Lib/"* | tail -1)/um/arm64" \
  --libdir "$(ls -d "$XWIN_SYSROOT/VC/Tools/MSVC/"* | tail -1)/lib/arm64" --libdir "$DEPS/lib"

echo "== OptiScaler"
commit=$(git -C "$SRC" rev-parse --short=8 HEAD 2>/dev/null || echo unknown)
cmake -S "$here/cmake" -B "$OUT/build" -G Ninja -DCMAKE_BUILD_TYPE=Release \
  -DCMAKE_TOOLCHAIN_FILE="$here/cmake/toolchain-clangcl-arm64ec.cmake" \
  -DOPTI_SRC="$SRC" -DOPTI_DEPS="$DEPS" -DOPTI_BUILD_COMMIT="$commit" >/dev/null
cmake --build "$OUT/build" -- -k 0

dll=$OUT/build/OptiScaler.dll
echo "== verify $dll"
python3 -I - "$dll" <<'PY'
import struct, sys
b = open(sys.argv[1], "rb").read()
pe = struct.unpack_from("<I", b, 0x3C)[0]
machine = struct.unpack_from("<H", b, pe + 4)[0]
# An ARM64EC image carries the x64 machine type plus CHPE metadata in its load config.
if machine != 0x8664:
    sys.exit(f"unexpected machine 0x{machine:04x}")
print(f"PE machine 0x{machine:04x} (x64 header, ARM64EC code), {len(b) // 1024} KiB")
PY
# Capture first: grep -q exits early, and under pipefail readobj's broken pipe fails the check.
loadcfg=$(llvm-readobj$LLVM_SUFFIX --coff-load-config "$dll")
grep -q CHPEMetadataPointer <<<"$loadcfg" || { echo "no CHPE metadata: not ARM64EC" >&2; exit 1; }
echo "ok"

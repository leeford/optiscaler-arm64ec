#!/bin/bash
# Build the ARM64EC dependency libraries from source into $DEPS_PREFIX.
#   DEPS_SRC     checkouts: detours/ (microsoft/Detours), freetype/ (VER-2-13-3)
#   DEPS_PREFIX  install prefix (lib/, include/)
# Needs XWIN_SYSROOT and LLVM_SUFFIX, as for the main build.
set -euo pipefail
here=$(cd "$(dirname "$0")/.." && pwd)
: "${DEPS_SRC:?}" "${DEPS_PREFIX:?}" "${XWIN_SYSROOT:?}"
tc="$here/cmake/toolchain-clangcl-arm64ec.cmake"
work=${DEPS_BUILD:-$DEPS_SRC/_build}
common=(-G Ninja -DCMAKE_BUILD_TYPE=Release -DCMAKE_TOOLCHAIN_FILE="$tc"
        -DCMAKE_INSTALL_PREFIX="$DEPS_PREFIX" -DCMAKE_MSVC_RUNTIME_LIBRARY=MultiThreadedDLL)

echo "== Detours"
cmake -S "$here/cmake/deps/detours" -B "$work/detours" "${common[@]}" -DDETOURS_SRC="$DEPS_SRC/detours"
cmake --build "$work/detours" --target install

echo "== FreeType"
cmake -S "$DEPS_SRC/freetype" -B "$work/freetype" "${common[@]}" \
  -DBUILD_SHARED_LIBS=OFF -DFT_DISABLE_ZLIB=ON -DFT_DISABLE_BZIP2=ON -DFT_DISABLE_PNG=ON \
  -DFT_DISABLE_HARFBUZZ=ON -DFT_DISABLE_BROTLI=ON -DCMAKE_C_FLAGS_RELEASE="/O2 /DNDEBUG -Wno-everything"
cmake --build "$work/freetype" --target install
# FreeType puts its version resource (.res) into the archive; lld only wants objects.
for m in $(llvm-ar${LLVM_SUFFIX:-} t "$DEPS_PREFIX/lib/freetype.lib" | grep '\.res$' || true); do
  llvm-ar${LLVM_SUFFIX:-} d "$DEPS_PREFIX/lib/freetype.lib" "$m"
done
ls "$DEPS_PREFIX/lib"

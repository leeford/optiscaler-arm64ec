#!/bin/bash
# Package the ARM64EC build for the Armada Decky plugin.
#
#   scripts/package.sh [SRC_DIR] [DLL] [DIST_DIR]
#
# Writes $DIST_DIR/OptiScaler-arm64ec-<upstream sha>.zip and release-notes.md.
# Zip layout (the plugin wants OptiScaler.dll at the root and copies
# OptiScaler.ini, README.md and licenses/; the fork also copies OptiScaler/):
#
#   OptiScaler.dll                 ARM64EC proxy (rename to dxgi.dll etc.)
#   OptiScaler.ini                 overlay on Insert (ShortcutKey=0x2D)
#   README.md
#   licenses/                      GPL-3.0 (OptiScaler), BSD-3 (SGSR), vendor licences
#   OptiScaler/                    x64 XeSS / FidelityFX runtimes, loaded under emulation
#   OptiScaler/D3D12_OptiScaler/   D3D12 Agility SDK runtime
set -euo pipefail
here=$(cd "$(dirname "$0")/.." && pwd)
SRC=$(cd "${1:-$PWD/src}" && pwd)
DLL=${2:-$PWD/out/build/OptiScaler.dll}
DIST=${3:-$PWD/dist}
OVERLAY_KEY=${OVERLAY_KEY:-0x2D}   # VK_INSERT

# The mainline commit the patch series was applied on (set by prepare-source.sh).
base=$(git -C "$SRC" rev-parse refs/upstream-base)
short=$(git -C "$SRC" rev-parse --short=7 "$base")
ver() { sed -n "s/^#define VER_$1 \([0-9]*\).*/\1/p" "$SRC/OptiScaler/resource.h" | head -1; }
version="v$(ver MAJOR_VERSION).$(ver MINOR_VERSION).$(ver HOTFIX_VERSION)"
repo_rev=$(git -C "$here" rev-parse --short=7 HEAD 2>/dev/null || echo local)

stage=$(mktemp -d)
trap 'rm -rf "$stage"' EXIT
p=$stage/pkg
mkdir -p "$p/licenses" "$p/OptiScaler/D3D12_OptiScaler"

cp "$DLL" "$p/OptiScaler.dll"
# CRLF is preserved; only the overlay key and log level values change.
# LogLevel auto means trace, which flushes to disk on every line (about 4 MB a minute
# in game) and makes OptiScaler warn on screen after 10 minutes. Info keeps a log for
# failed launches.
sed -E -e "s/^(ShortcutKey=)[^;\r]*/\1$OVERLAY_KEY/" -e "s/^(LogLevel=)[^;\r]*/\12/" \
  "$SRC/OptiScaler.ini" > "$p/OptiScaler.ini"
grep -q "^ShortcutKey=$OVERLAY_KEY" "$p/OptiScaler.ini" || { echo "ShortcutKey not set" >&2; exit 1; }
grep -q "^LogLevel=2" "$p/OptiScaler.ini" || { echo "LogLevel not set" >&2; exit 1; }
cp "$here/docs/PACKAGE-README.md" "$p/README.md"

E=$SRC/external
cp "$E"/xess/bin/libxess.dll "$E"/xess/bin/libxess_dx11.dll "$E"/xess/bin/libxess_fg.dll "$E"/xess/bin/libxell.dll "$p/OptiScaler/"
cp "$E"/FidelityFX-SDK-v2/Kits/FidelityFX/signedbin/amd_fidelityfx_*.dll "$p/OptiScaler/"
cp "$E"/directx_agility_sdk/lib/D3D12Core.dll "$p/OptiScaler/D3D12_OptiScaler/"

cp "$SRC/LICENSE" "$p/licenses/OptiScaler-GPL-3.0.txt"
cp "$SRC/OptiScaler/upscalers/sgsr2/shaders/SGSR_LICENSE.txt" "$p/licenses/SGSR_LICENSE.txt"
cp "$E/xess/LICENSE.txt" "$p/licenses/XeSS_LICENSE.txt"
cp "$E/FidelityFX-SDK/docs/license.md" "$p/licenses/FidelityFX_v1_LICENSE.md" 2>/dev/null || true
cp "$E/FidelityFX-SDK-v2/docs/license.md" "$p/licenses/FidelityFX_v2_LICENSE.md" 2>/dev/null || true
cp "$E/directx_agility_sdk/LICENSE.txt" "$p/licenses/DirectX_LICENSE.txt"
cp "$here/LICENSE" "$p/licenses/optiscaler-arm64ec-build-GPL-3.0.txt"

mkdir -p "$DIST"
DIST=$(cd "$DIST" && pwd)
zip_name="OptiScaler-arm64ec-$short.zip"
rm -f "$DIST"/OptiScaler-arm64ec-*.zip
(cd "$p" && find . -type f | LC_ALL=C sort | zip -q -X -9 "$DIST/$zip_name" -@)

cat > "$DIST/release-notes.md" <<EOF
Unofficial ARM64EC build of [OptiScaler](https://github.com/optiscaler/OptiScaler) for Proton ARM64 (Armada OS, FEX, Turnip).

**Base version:** $version
**Build commit:** $short
**Upstream commit:** [\`$base\`](https://github.com/optiscaler/OptiScaler/commit/$base)
**Build repo revision:** $repo_rev

Includes SGSR 1 and 2 (DX11, DX12, Vulkan) and the ARM64EC/Wine fixes from
[nydal91/optiscaler_arm64ec](https://github.com/nydal91/optiscaler_arm64ec).
Built on Linux with clang-cl. Overlay key: **Insert**.

SHA-256: \`$(sha256sum "$DIST/$zip_name" | cut -d' ' -f1)\`
EOF
echo "$DIST/$zip_name"
unzip -l "$DIST/$zip_name" | tail -n +4 | head -n -2 | awk '{print "  " $4}'

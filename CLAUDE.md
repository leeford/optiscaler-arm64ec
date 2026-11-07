# optiscaler-arm64ec: notes for Claude Code sessions

Owner: leeford. Target: a Snapdragon handheld running Armada OS (Fedora
bootc, SteamOS-like). Games run under Proton ARM64 (Wine ARM64EC) + FEX + Turnip.
The owner works on Fedora and prefers bash over PowerShell. README.md covers usage;
this file covers state and decisions.

## What this repo is

A patch series plus a Linux build for mainline OptiScaler, not a fork of it.
`scripts/prepare-source.sh` clones optiscaler/OptiScaler at a ref into `src/`,
applies `patches/*.patch` with `git am -3`, and patches the `unordered_dense`
submodule. `scripts/build.sh` builds with clang-cl/lld-link (LLVM 22) against the
MSVC CRT + Windows SDK from xwin. `scripts/package.sh` makes the zip the Decky
plugin installs. `.github/workflows/sync-build.yml` does it daily on ubuntu-24.04.

## Decisions already made (don't relitigate without the owner)

- Linux-only build (no Windows runner). A Windows/MSVC comparison build was offered
  as an optional extra and not yet requested.
- Patch series on top of fresh mainline, not a submodule or a long-lived fork.
- Patches came from nydal91/optiscaler_arm64ec (ARM64EC hooks, SGSR 1/2, Wine and
  Adreno fixes) rebased onto mainline d94fb15, plus `0018-Build-with-clang-cl`.
  README-only patches (0015, 0017) were dropped to avoid needless conflicts.
- Overlay key: Insert (`ShortcutKey=0x2D`, set at package time).
- Release asset: exactly one `OptiScaler-arm64ec-<upstream sha7>.zip`; notes carry
  `Base version:` and `Build commit:` lines that the plugin parses.
- Repo is public so the plugin can download releases anonymously.

## Non-obvious build details (each was a real failure)

- ARM64EC predefines `__x86_64__`/`_M_X64`; the SDK's DirectXMath.h then includes
  clang's x86 `cpuid.h`. `cmake/compat/cpuid.h` shadows it.
- `cmake/compat/arm64ec_compat.h` (force-included) supplies `_mm_pause`/fences,
  which MSVC emulates on ARM64EC and clang does not.
- The SDK's arm64 UCRT import lib has no EC entries; `scripts/make-ucrt-arm64ec.py`
  generates `ucrt/arm64ec/ucrt.lib` from the x64 one (setup-toolchain does this).
- `Source.def` names C++ functions undecorated; `scripts/resolve-def.py` maps them
  to the `$$h` (ARM64EC-native) mangled symbols. Exporting the x64 alias fails
  when the name is also an import (AppCacheCheckManifest).
- Windows-cased includes and `#pragma comment(lib, ...)` names are fixed by
  `scripts/fix-include-case.py` with symlinks.
- SGSR DX11/DX12 shaders are compiled at build time by Microsoft's fxc.exe (from
  the Windows SDK MSI) under Wine (`scripts/fxc.sh`).
- Detours and FreeType 2.13.3 are built from source; FidelityFX FSR 2/3 static libs
  are still prebuilt (`prebuilt/fsr-arm64ec`, see PROVENANCE.md).
- Full package is ~180 MB because of the x64 XeSS/FidelityFX runtimes.
- `0019` skips `hookGdi32()` on ARM64EC: clang-cl compiled `hkD3DKMTQueryAdapterInfo`
  to a lone `BRK #1`, so D3D11 games died at launch (illegal instruction at
  `dxgi.dll+0x8312C` in the d94fb15 build). Root cause in clang not yet found; mainline
  added the hook on 2026-10-05, after Sloptiscaler's base, which is why that build is fine.
- CI scripts run under `set -o pipefail`: never pipe into `grep -q` (broken pipe fails it).

## Decky plugin

`decky-plugin/*.patch` are commits for a fork of justradical/decky-optiscaler-arm64ec
(on top of its commit 8c492ca): download from leeford/optiscaler-arm64ec, install the
`OptiScaler/` runtime folder, case-insensitive `licenses/`, backups keyed by relative
path, and `<plugin data dir>/source.json` (`{"repo": ..., "tag": ...}`) to switch
repo or pin a release for rollback. Apply with `git am decky-plugin/*.patch` in a
clone of the fork.

## Open items

1. First GitHub Actions run (started 2026-11-07): confirm it publishes a release.
2. Fork justradical/decky-optiscaler-arm64ec to leeford, apply `decky-plugin/` patches, push.
3. Hand test on the handheld: overlay on Insert, SGSR 2 / FSR selectable, and
   10-launch boot reliability vs Sloptiscaler (which boots ~1 in 10). Collect
   OptiScaler.log from any failed launch.
4. Later: build FSR 2/3 libs from source; optional Windows/MSVC A/B build;
   maybe HelixSR integration (closed-source x64 DLL under a no-redistribution
   licence: would need porting HelixSR-Scaler's GPL integration as a patch and
   the user installing HelixSR themselves; first check its speed test on Adreno).

## Suspected cause of Sloptiscaler's boot failures (unconfirmed)

Sloptiscaler is based on mainline of 2026-09-18 and lacks mainline fixes such as
83e18f1 (launch deadlock in LibraryLoad_Hooks), f6db41d (sl plugin hook races),
2d91b8e (thread-local creatingD3DDevice), and nydal91's winevulkan swapchain
guard. It is also built with llvm-mingw rather than an MSVC-ABI toolchain.

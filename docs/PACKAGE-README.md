# OptiScaler ARM64EC

Unofficial ARM64EC build of OptiScaler for Proton ARM64 (Wine ARM64EC + FEX),
for example on Armada OS. Includes SGSR 1 and SGSR 2 for DX11, DX12 and Vulkan.

## Files

| Path | What it is |
|---|---|
| `OptiScaler.dll` | ARM64EC proxy. Rename to `dxgi.dll` (default), `winmm.dll` or `version.dll`. |
| `OptiScaler.ini` | Settings. The overlay opens with **Insert**. |
| `OptiScaler/` | x64 XeSS and FidelityFX runtimes. They run under FEX emulation. |
| `licenses/` | OptiScaler is GPL-3.0, SGSR is BSD-3-Clause, plus the vendor licences. |

## Manual install

1. Copy everything next to the game's real executable. For Unreal Engine games
   that is `<Game>/Binaries/Win64`. Keep the folder names' case.
2. Rename `OptiScaler.dll` to `dxgi.dll`.
3. Steam launch options: `WINEDLLOVERRIDES="dxgi=n,b" %command%`

With the Armada Decky plugin, install from the plugin instead. It does all
three steps.

# optiscaler-arm64ec

Automated ARM64EC builds of [OptiScaler](https://github.com/optiscaler/OptiScaler)
for Proton ARM64 (Wine ARM64EC + FEX + Turnip), packaged for the
[Armada OS](https://github.com/armada-os/armada) Decky plugin.

- Tracks mainline: a daily workflow applies this repo's patches to the latest
  `optiscaler/OptiScaler` master, builds, and publishes a release.
- Includes SGSR 1 and SGSR 2 (DX11, DX12, Vulkan), the Adreno FSR 2/3 fixes and
  the Wine/Vulkan fixes from [nydal91/optiscaler_arm64ec](https://github.com/nydal91/optiscaler_arm64ec).
- Built entirely on Linux: clang-cl + lld-link, Microsoft's CRT and Windows SDK
  via [xwin](https://github.com/Jake-Shadle/xwin), and Microsoft's `fxc` under Wine
  for the SGSR shaders. No Windows or Visual Studio involved.
- Overlay key: **Insert**.

## How it works

This repo holds no copy of OptiScaler. It holds the changes on top of it:

| Path | Purpose |
|---|---|
| `patches/*.patch` | The ARM64EC, SGSR and Wine changes, as a `git am` series |
| `patches/submodules/` | `unordered_dense` fix (`_umul128` does not exist on ARM64EC) |
| `cmake/` | Linux build replacing the Visual Studio project; sources are globbed |
| `cmake/compat/` | Header shims for clang-cl on ARM64EC |
| `prebuilt/fsr-arm64ec/` | FidelityFX FSR 2/3 static libs (see `PROVENANCE.md`) |
| `scripts/` | `setup-toolchain.sh`, `prepare-source.sh`, `build.sh`, `package.sh`, `refresh-patches.sh` |

Each run of `.github/workflows/sync-build.yml`:

1. Skips if neither mainline nor this repo changed since the last release.
2. Applies `patches/` to mainline master. If a patch no longer applies, the run
   fails and opens (or comments on) an issue labelled `upstream-conflict` that
   names the failing patch and the conflicting files.
3. Builds and checks that the DLL really is ARM64EC.
4. Publishes a release with a single asset, `OptiScaler-arm64ec-<upstream sha>.zip`,
   and notes containing `Base version:` and `Build commit:`, which the plugin reads.
5. Closes any open `upstream-conflict` issue.

Run it by hand from **Actions → Sync mainline and build ARM64EC → Run workflow**
(optionally with another upstream ref, or `force` to rebuild).

## Install on Armada

The plugin installs `OptiScaler.dll`, the ini and the `OptiScaler/` runtime
folder into the game, renames the DLL, and sets the launch options.

**Option A: the forked plugin (recommended).** The fork in
`YOUR_GITHUB_USER/decky-optiscaler-arm64ec` downloads from this repo and also
installs the `OptiScaler/` runtimes (XeSS, FidelityFX, D3D12 Agility). Build it
with `pnpm install && pnpm build`, zip it as Decky expects, and in Decky turn on
**Developer mode** and use **Install plugin from ZIP**.

**Option B: the stock plugin, one-line edit on the device.** In
`~/homebrew/plugins/<plugin folder>/py_modules/opti_release.py`, change

```python
REPO = "justradical/Sloptiscaler"
```

to `REPO = "YOUR_GITHUB_USER/optiscaler-arm64ec"`, then restart Decky:

```bash
sudo systemctl restart plugin_loader
```

The stock plugin only copies `OptiScaler.dll`, the ini and `README.md`, so the
XeSS and FidelityFX DLL runtimes are not installed. SGSR and the built-in FSR
2/3 still work. A plugin update reverts the edit. If Armada ships the plugin
inside the read-only OS image, use option A.

## Test on the handheld

1. In the plugin, **Download build** and check that the version shows the new
   commit. Then install OptiScaler into one game and keep the default `dxgi.dll`.
2. Launch the game ten times. Note any launch that hangs or crashes.
3. In game, press **Insert**. The OptiScaler overlay should open. If your
   controller has no Insert, map one in Steam Input (Keyboard → Insert).
4. In the overlay's upscaler list, pick SGSR 2 (or FSR 2/3/XeSS) and confirm the
   image changes.
5. If something fails, the log is `OptiScaler.log` next to the game executable.
   It is the first thing to attach to an issue.

## Roll back

- **To a previous build of this repo.** Create
  `~/homebrew/data/OptiScaler/source.json` (forked plugin) with the release tag
  from the Releases page:

  ```json
  {"tag": "arm64ec-20261107-d94fb15-abc1234"}
  ```

  Then **Download build** again. Delete the file to follow the newest release
  again.
- **Back to Sloptiscaler.** Use
  `{"repo": "justradical/Sloptiscaler", "tag": "finally"}` in the same file.
- **Offline.** Put any release zip in `~/Downloads`; the plugin falls back to
  it when GitHub is unreachable.
- **Remove from a game.** Uninstall it in the plugin. It restores any original
  `dxgi.dll` and other files it replaced.

## When the workflow reports a conflict

On your machine (see "Build locally" for the toolchain):

```bash
scripts/refresh-patches.sh
```

Resolve the files `git am` stops on in `src/`, then run:

```bash
git -C src add -A && git -C src am --continue
```

Repeat until the series is applied, then export and push:

```bash
scripts/refresh-patches.sh --export
```

```bash
git add patches && git commit -m "Rebase patches onto mainline" && git push
```

The push triggers a build. The next scheduled run releases it, or run the
workflow by hand.

## Build locally (Fedora)

The scripts target Ubuntu 24.04, like the GitHub runner, so on Fedora run them
in a container:

```bash
podman run --rm -it -v "$PWD":/w:Z -w /w ubuntu:24.04 bash -c '
  apt-get update -qq && apt-get install -y -qq sudo curl gnupg ca-certificates >/dev/null &&
  scripts/setup-toolchain.sh && source .tools/env.sh &&
  scripts/prepare-source.sh "$PWD/src" master &&
  scripts/build.sh "$PWD/src" "$PWD/out" &&
  scripts/package.sh "$PWD/src" "$PWD/out/build/OptiScaler.dll" "$PWD/dist"'
```

The zip lands in `dist/`. The first run downloads about 1.5 GB (LLVM, CRT and
SDK, Wine). Later runs reuse `.tools/`.

## Licences

- OptiScaler and this build repo: GPL-3.0 (`LICENSE`).
- SGSR: BSD-3-Clause.
- XeSS, FidelityFX and the DirectX Agility SDK: their own licences.

All of them ship in the release zip under `licenses/`. The Microsoft CRT and SDK
that xwin downloads are only used to build. They are not redistributed.

## Not done yet

- The FidelityFX FSR 2/3 static libraries are still prebuilt (MSVC, from
  nydal91's repo). Building them from source needs AMD's FidelityFX shader
  compiler under Wine for the shader permutations.
- Builds are untested on hardware until you try one.

# Prebuilt FidelityFX libraries (ARM64EC)

These static libraries are the FSR 2.2.1 (DX11/DX12/VK), FSR 2.1.2 (DX12/VK) and
FSR 3.1 (DX11 backend, upscaler, frame interpolation, optical flow) builds that
OptiScaler links. Mainline OptiScaler ships the x64 equivalents as binaries in
`OptiScaler/library/`; these are the ARM64EC counterparts.

- Source: [nydal91/optiscaler_arm64ec](https://github.com/nydal91/optiscaler_arm64ec)
  `arm64ec/libs/{fsr2,fsr2_212,fsr31}` at commit
  8c494c7aba183c32b4955622cec154adc90a924f
- Built there with MSVC v143 (`arm64ec/deps/build-fsr*.ps1`), plain COFF
  ARM64EC objects (no /GL), so lld-link can consume them.
- Licence: MIT (AMD FidelityFX), see `licenses/` in the release package.
- Checksums: `SHA256SUMS`; `scripts/build.sh` verifies them before linking.

Replacing these with libraries built from source on Linux is tracked as a TODO
in the README: it needs AMD's FidelityFX shader compiler (a Windows tool) run
under Wine for the shader permutations.

#!/usr/bin/env python3
"""Write the packaged OptiScaler.ini: mainline's ini plus this build's settings.

    scripts/configure-ini.py SRC_INI OUT_INI [--overlay-key 0x2D]

The patch series leaves OptiScaler.ini alone because upstream edits it almost
daily, so every change to it lives here. A setting that cannot be applied fails
the build; a note whose anchor key is gone only warns, since it is just a comment.
Line endings (CRLF upstream) are kept.
"""
import argparse
import re
import sys

ap = argparse.ArgumentParser()
ap.add_argument("src")
ap.add_argument("out")
ap.add_argument("--overlay-key", default="0x2D")  # VK_INSERT
args = ap.parse_args()

raw = open(args.src, "rb").read().decode("utf-8")
eol = "\r\n" if "\r\n" in raw else "\n"
text = raw.replace("\r\n", "\n")

# key -> value. LogLevel auto means trace, which flushes every line to disk and
# warns on screen after 10 minutes; Info keeps a log for failed launches.
SETTINGS = {
    "ShortcutKey": args.overlay_key,
    "LogToFile": "true",
    "LogLevel": "2",
}

# key -> comment lines inserted just above it.
NOTES = {
    "Dx11Upscaler": ["; ARM64EC build: also sgsr1 and sgsr2 (native DX11)"],
    "Dx12Upscaler": [
        "; ARM64EC build: also sgsr1 and sgsr2",
        "; On vkd3d-proton below SM 6.4 (Adreno) auto uses fsr22 instead of XeSS, which is very slow there",
    ],
    "VulkanUpscaler": ["; ARM64EC build: also sgsr1 and sgsr2 (native VK)"],
}

failed = False
for key, value in SETTINGS.items():
    text, n = re.subn(rf"^({re.escape(key)}=)[^;\n]*", lambda m: m.group(1) + value, text, flags=re.M)
    if n != 1:
        print(f"configure-ini: expected one {key}= line, found {n}", file=sys.stderr)
        failed = True

for key, lines in NOTES.items():
    text, n = re.subn(rf"^(?={re.escape(key)}=)", "\n".join(lines) + "\n", text, count=1, flags=re.M)
    if n != 1:
        print(f"configure-ini: warning: no {key}= line, note skipped", file=sys.stderr)

if failed:
    sys.exit(1)
open(args.out, "wb").write(text.replace("\n", eol).encode("utf-8"))

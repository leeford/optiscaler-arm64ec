#!/usr/bin/env python3
"""Build an ARM64EC import library for the Universal CRT.

The Windows SDK's ucrt.lib exists only as x64 and pure ARM64 import libraries.
ARM64EC code needs ARM64EC import entries: clang emits direct calls to math
routines (`#sin`, `#fmodf`, ...) that only an EC import library provides. This
reads the DLL and symbol of every import member of the x64 ucrt.lib and writes
an equivalent ARM64EC import library with llvm-lib /def.

usage: make-ucrt-arm64ec.py X64_UCRT_LIB OUT_LIB LLVM_SUFFIX
"""
import os
import re
import subprocess
import sys
import tempfile
from collections import defaultdict


def main():
    src, out, suffix = sys.argv[1], sys.argv[2], sys.argv[3] if len(sys.argv) > 3 else ""
    nm = subprocess.run([f"llvm-nm{suffix}", "-A", src], check=True,
                        capture_output=True, text=True).stdout
    # "ucrt.lib:api-ms-win-crt-math-l1-1-0.dll: 00000000 T sin"
    syms = defaultdict(set)
    for line in nm.splitlines():
        m = re.match(r"^[^:]+:([^:]+\.dll):\s+\S+\s+\S\s+(\S+)$", line, re.I)
        if m:
            syms[m.group(1)].add(m.group(2))

    with tempfile.TemporaryDirectory() as tmp:
        libs = []
        for dll, names in sorted(syms.items()):
            exports = []
            for name in sorted(names):
                if name.startswith("__imp_"):
                    base = name[len("__imp_"):]
                    # Only an __imp_ symbol and no thunk: a data export.
                    if base not in names:
                        exports.append(f"{base} DATA")
                else:
                    exports.append(name)
            exports = sorted(set(e for e in exports if not e.startswith("__IMPORT_DESCRIPTOR")
                                 and not e.startswith("__NULL_IMPORT") and "_NULL_THUNK_DATA" not in e))
            stem = dll[:-4]
            dfile = os.path.join(tmp, stem + ".def")
            with open(dfile, "w") as handle:
                handle.write(f"LIBRARY {dll}\nEXPORTS\n")
                handle.write("".join(f"  {e}\n" for e in exports))
            lib = os.path.join(tmp, stem + ".lib")
            subprocess.run([f"llvm-lib{suffix}", "/nologo", "/machine:arm64ec",
                            f"/def:{dfile}", f"/out:{lib}"], check=True)
            libs.append(lib)
        os.makedirs(os.path.dirname(out), exist_ok=True)
        subprocess.run([f"llvm-lib{suffix}", "/nologo", "/machine:arm64ec", f"/out:{out}"] + libs, check=True)
    print(f"{out}: {sum(len(v) for v in syms.values())} symbols from {len(syms)} DLLs")


if __name__ == "__main__":
    main()

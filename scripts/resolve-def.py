#!/usr/bin/env python3
"""Resolve undecorated names in a .def file to the C++ symbols that define them.

OptiScaler's Source.def exports e.g. `CreateDXGIFactory = _CreateDXGIFactory`
while `_CreateDXGIFactory` is a C++ function (`?_CreateDXGIFactory@@YAJ...`).
MSVC's link.exe matches such names to the decorated symbol on its own;
lld-link does not. Rewrite each internal name that is not defined as-is to the
unique decorated symbol whose name it is. On ARM64EC that is the native `$$h`
symbol: lld then emits the x64 entry thunk, as link.exe does (exporting the
x64-mangled alias instead fails when the export name is also an import, e.g.
AppCacheCheckManifest from kernel32).

usage: resolve-def.py IN.def OUT.def NM OBJ...    (NM: llvm-nm binary)
"""
import re
import subprocess
import sys


def main():
    src, dst, nm, objs = sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4:]
    defined = set()
    # Pass the object list through a response file: there are hundreds.
    rsp = dst + ".objs"
    with open(rsp, "w") as handle:
        handle.write("\n".join(objs))
    out = subprocess.run([nm, "--defined-only", "--format=just-symbols", "@" + rsp],
                         check=True, capture_output=True, text=True).stdout
    for line in out.splitlines():
        line = line.strip()
        if line and not line.endswith(":"):
            defined.add(line)
    weak = subprocess.run([nm, "--format=posix", "@" + rsp],
                          check=True, capture_output=True, text=True).stdout
    for line in weak.splitlines():
        parts = line.split()
        if len(parts) >= 2 and parts[1] in ("w", "W"):
            defined.add(parts[0])

    by_name = {}
    for sym in defined:
        m = re.match(r"^\?([A-Za-z_][A-Za-z0-9_]*)@@", sym)
        if m:
            by_name.setdefault(m.group(1), set()).add(sym)

    text = open(src, encoding="utf-8-sig").read()
    missing = []

    def fix(m):
        external, internal, rest = m.group(1), m.group(2), m.group(3)
        if internal in defined:
            return m.group(0)
        cands = sorted(by_name.get(internal, ()))
        native = [c for c in cands if "$$h" in c]
        pick = native or cands
        if len(pick) != 1:
            missing.append(f"{internal}: {len(pick)} candidates")
            return m.group(0)
        return f"{external} = {pick[0]}{rest}"

    pattern = re.compile(r"^(\s*[A-Za-z_][A-Za-z0-9_]*)\s*=\s*([A-Za-z_][A-Za-z0-9_]*)(.*)$", re.M)
    text = pattern.sub(fix, text)
    if missing:
        sys.exit("resolve-def: cannot resolve " + "; ".join(missing))
    open(dst, "w", encoding="utf-8").write(text)


if __name__ == "__main__":
    main()

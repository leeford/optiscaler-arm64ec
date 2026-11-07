#!/usr/bin/env python3
"""Make #include spellings resolve on a case-sensitive filesystem.

OptiScaler is developed on Windows, where `#include "config.h"` finds
`Config.h`. For every #include in the scanned trees that does not resolve
exactly but does resolve case-insensitively (relative to the including file or
to one of the --include dirs), create a symlink with the requested spelling.

usage: fix-include-case.py --scan DIR... --include DIR... [--libdir DIR...]

--libdir does the same for `#pragma comment(lib, ...)` names (lld-link
looks them up case-sensitively on Linux).
"""
import argparse
import os
import re
import sys

INCLUDE_RE = re.compile(rb'^\s*#\s*include\s*[<"]([^>"]+)[>"]', re.M)
# #pragma comment(lib, "Version.lib") is resolved by the linker, also by name.
LIB_RE = re.compile(rb'#\s*pragma\s+comment\s*\(\s*lib\s*,\s*"([^"]+)"', re.I)
EXTS = (".c", ".cc", ".cpp", ".cxx", ".h", ".hh", ".hpp", ".hxx", ".inl", ".rc")


def ci_resolve(base, rel):
    """Return the real path of base/rel matched case-insensitively, or None."""
    cur = base
    for part in rel.replace("\\", "/").split("/"):
        if part in ("", "."):
            continue
        if part == "..":
            cur = os.path.dirname(cur)
            continue
        exact = os.path.join(cur, part)
        if os.path.exists(exact):
            cur = exact
            continue
        try:
            names = os.listdir(cur)
        except OSError:
            return None
        low = part.lower()
        match = [n for n in names if n.lower() == low]
        if not match:
            return None
        cur = os.path.join(cur, match[0])
    return cur if os.path.isfile(cur) else None


def link(base, rel, real):
    """Create base/rel (requested spelling) pointing at real, segment by segment."""
    cur = base
    parts = [p for p in rel.replace("\\", "/").split("/") if p not in ("", ".")]
    for i, part in enumerate(parts):
        if part == "..":
            cur = os.path.dirname(cur)
            continue
        want = os.path.join(cur, part)
        if not os.path.lexists(want):
            low = part.lower()
            match = [n for n in os.listdir(cur) if n.lower() == low]
            if not match:
                return False
            os.symlink(match[0], want)
            print(f"  {os.path.relpath(want)} -> {match[0]}")
        cur = want
    return True


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--scan", action="append", required=True)
    ap.add_argument("--include", action="append", default=[])
    ap.add_argument("--libdir", action="append", default=[])
    args = ap.parse_args()

    fixed = 0
    for root in args.scan:
        for dirpath, _dirs, files in os.walk(root):
            for name in files:
                if not name.lower().endswith(EXTS):
                    continue
                path = os.path.join(dirpath, name)
                try:
                    data = open(path, "rb").read()
                except OSError:
                    continue
                for m in LIB_RE.finditer(data):
                    lib = m.group(1).decode("utf-8", "replace")
                    if not lib.lower().endswith(".lib"):
                        lib += ".lib"
                    if any(os.path.isfile(os.path.join(d, lib)) for d in args.libdir):
                        continue
                    for d in args.libdir:
                        real = ci_resolve(d, lib)
                        if real and link(d, lib, real):
                            fixed += 1
                            break
                for m in INCLUDE_RE.finditer(data):
                    rel = m.group(1).decode("utf-8", "replace").replace("\\", "/")
                    bases = [dirpath] + args.include
                    if any(os.path.isfile(os.path.join(b, rel)) for b in bases):
                        continue
                    for b in bases:
                        real = ci_resolve(b, rel)
                        if real and link(b, rel, real):
                            fixed += 1
                            break
    print(f"fix-include-case: {fixed} link(s) created")
    return 0


if __name__ == "__main__":
    sys.exit(main())

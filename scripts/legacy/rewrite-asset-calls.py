#!/usr/bin/env python3
"""Route UIImage(named:) through LegacyAssets.image(_:).

The armv7 build has no asset catalog (actool is macOS-only), so template
rendering intent has to be reapplied at load time -- see LegacyAssets. This
rewrite is mechanical and idempotent, so it can be re-run after every merge
from upstream rather than hand-resolved:

    git merge upstream -> take upstream's side -> re-run -> commit

Skips LegacyAssets.swift itself, and anything already rewritten.
"""
import argparse
import re
import sys
from pathlib import Path

PATTERN = re.compile(r"\bUIImage\(named:\s*")
SKIP = {"LegacyAssets.swift"}


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--root", default=".")
    g = ap.add_mutually_exclusive_group(required=True)
    g.add_argument("--apply", action="store_true")
    g.add_argument("--check", action="store_true")
    args = ap.parse_args()

    root = Path(args.root).resolve()
    total = 0
    for path in sorted(list((root / "Opaline").rglob("*.swift"))
                       + list((root / "OpalineOpenIn").rglob("*.swift"))):
        if path.name in SKIP:
            continue
        src = path.read_text(encoding="utf-8")
        hits = len(PATTERN.findall(src))
        if not hits:
            continue
        total += hits
        rel = path.relative_to(root)
        print(f"{rel}: {hits}")
        if args.apply:
            path.write_text(PATTERN.sub("LegacyAssets.image(", src), encoding="utf-8")

    verb = "rewrote" if args.apply else "found"
    print(f"\n{verb} {total} UIImage(named:) call site(s)", file=sys.stderr)
    return 1 if (args.check and total) else 0


if __name__ == "__main__":
    sys.exit(main())

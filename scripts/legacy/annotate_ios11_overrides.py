#!/usr/bin/env python3
"""Annotate overrides of iOS 11+ UIKit members with their availability.

Upstream deploys to iOS 12, so these overrides need no annotation there and have
none.  At a 9.3 deployment target the compiler rejects them -- and a compat shim
cannot help, because Swift does not allow overriding a member declared in an
extension.  Annotating the override itself is the supported way to override
newer API while deploying older, and it is semantically neutral on iOS 12, which
makes it a good candidate to send upstream rather than carry forever.

Idempotent; rerun after every upstream merge.

    annotate_ios11_overrides.py --report | --check | --apply
"""
import argparse
import pathlib
import re
import sys

REPO = pathlib.Path(__file__).resolve().parents[2]
# Members introduced in iOS 11 that this tree overrides.
MEMBERS = ("prefersHomeIndicatorAutoHidden", "viewSafeAreaInsetsDidChange")
PATTERN = re.compile(
    r"^(?P<indent>\s*)override\s+(?:var|func)\s+(?P<name>" + "|".join(MEMBERS) + r")\b"
)
ANNOTATION = "@available(iOS 11.0, *)"


def sites():
    found = []
    for path in sorted((REPO / "Opaline").rglob("*.swift")):
        lines = path.read_text().splitlines()
        for index, line in enumerate(lines):
            match = PATTERN.match(line)
            if not match:
                continue
            # Already annotated on the line above?
            if index and ANNOTATION in lines[index - 1]:
                continue
            found.append((path, index, match.group("indent"), match.group("name")))
    return found


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    group = parser.add_mutually_exclusive_group(required=True)
    group.add_argument("--report", action="store_true")
    group.add_argument("--check", action="store_true")
    group.add_argument("--apply", action="store_true")
    args = parser.parse_args()

    found = sites()
    for path, index, _, name in found:
        print(f"  {path.relative_to(REPO)}:{index + 1}  override {name}")
    print(f"{len(found)} override(s) needing {ANNOTATION}")
    if args.check:
        return 1 if found else 0
    if not args.apply:
        return 0

    by_file = {}
    for path, index, indent, _ in found:
        by_file.setdefault(path, []).append((index, indent))
    for path, positions in by_file.items():
        lines = path.read_text().splitlines(keepends=True)
        for index, indent in sorted(positions, reverse=True):
            lines.insert(index, f"{indent}{ANNOTATION}\n")
        path.write_text("".join(lines))
    print(f"annotated {len(found)} override(s)")
    return 0


if __name__ == "__main__":
    sys.exit(main())

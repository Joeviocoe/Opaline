#!/usr/bin/env python3
"""Restore explicit `self.` where Swift 5.8's SE-0365 lets it be implicit.

Upstream targets a modern Swift, where `guard let self = self else { return }`
unwraps `self` for the rest of an escaping closure and later references need no
prefix.  That is SE-0365, which landed in Swift 5.8; the armv7 toolchain is
Swift 5.4.2, so every one of those references is an error there.

The rewrite is driven by the compiler's own diagnostics rather than by matching
source patterns.  That matters: deciding textually which `foo` is a member of
`self` and which is a local means reimplementing name lookup, whereas the
compiler has already done it exactly.  Fixing one reference can reveal the next
in the same expression, so it iterates until the diagnostics stop.

Idempotent, like its sibling downgrade_swift56.py: rerun it after every upstream
merge.

    downgrade_implicit_self.py --report   what would change
    downgrade_implicit_self.py --check    exit 1 if any site remains
    downgrade_implicit_self.py --apply    rewrite in place
"""
import argparse
import pathlib
import re
import subprocess
import sys

REPO = pathlib.Path(__file__).resolve().parents[2]
# Both spellings the compiler uses for this one situation.
DIAG = re.compile(
    r"^(?P<path>.+?):(?P<line>\d+):(?P<col>\d+): error: "
    r"(?:reference to property .+? in closure requires explicit use of 'self'"
    r"|call to method .+? in closure requires explicit use of 'self'"
    r"|implicit use of 'self' in closure)"
)
# Darling shows the host filesystem here, so diagnostics carry the prefix.
VOLUME = "/Volumes/SystemRoot"
MAX_ROUNDS = 12


def diagnose():
    """Type-check and return [(path, line, col)] needing an explicit self."""
    result = subprocess.run(
        [str(REPO / "scripts/legacy/typecheck.sh")],
        capture_output=True, text=True,
    )
    sites = []
    for raw in (result.stdout + result.stderr).splitlines():
        match = DIAG.match(raw.strip())
        if not match:
            continue
        path = match.group("path")
        if path.startswith(VOLUME):
            path = path[len(VOLUME):]
        sites.append((pathlib.Path(path), int(match.group("line")), int(match.group("col"))))
    return sites


def apply(sites):
    """Insert `self.` at each site, right-to-left so columns stay valid."""
    changed = 0
    by_file = {}
    for path, line, col in sites:
        by_file.setdefault(path, []).append((line, col))
    for path, positions in by_file.items():
        if not path.exists():
            print(f"  skipped, no such file: {path}", file=sys.stderr)
            continue
        lines = path.read_text().splitlines(keepends=True)
        # Descending, so an earlier insertion never shifts a later column.
        for line, col in sorted(set(positions), reverse=True):
            text = lines[line - 1]
            index = col - 1
            if text[index:index + 5] == "self.":
                continue
            lines[line - 1] = text[:index] + "self." + text[index:]
            changed += 1
        path.write_text("".join(lines))
    return changed


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    group = parser.add_mutually_exclusive_group(required=True)
    group.add_argument("--report", action="store_true")
    group.add_argument("--check", action="store_true")
    group.add_argument("--apply", action="store_true")
    args = parser.parse_args()

    sites = diagnose()
    if args.report or args.check:
        for path, line, col in sites:
            print(f"  {path.relative_to(REPO)}:{line}:{col}")
        print(f"{len(sites)} site(s) need an explicit self")
        return 1 if (args.check and sites) else 0

    total = 0
    for round_number in range(1, MAX_ROUNDS + 1):
        if not sites:
            break
        count = apply(sites)
        total += count
        print(f"  round {round_number}: {count} inserted")
        if count == 0:
            break
        sites = diagnose()
    print(f"{total} explicit self insertion(s)")
    return 0


if __name__ == "__main__":
    sys.exit(main())

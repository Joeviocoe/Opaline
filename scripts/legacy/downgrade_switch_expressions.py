#!/usr/bin/env python3
"""Turn Swift 5.9 `switch` expressions back into explicit `return` statements.

SE-0380 let a `switch` be an expression, so upstream writes

    var name: String {
        switch self {
        case .a: "A"
        case .b: "B"
        }
    }

Swift 5.4 needs `return` on each arm.  Note this is invisible to `-typecheck`:
"missing return" comes out of SILGen, not the type checker, so only a real
compile finds these -- which is why they survived a clean type-check.

Driven by the compiler's diagnostics rather than by guessing which switches are
expressions: the diagnostic names the exact function, and anything it does not
name is already correct.  Idempotent; rerun after every upstream merge.

    downgrade_switch_expressions.py --report | --check | --apply [--log FILE]
"""
import argparse
import glob
import os
import pathlib
import re
import sys

REPO = pathlib.Path(__file__).resolve().parents[2]
VOLUME = "/Volumes/SystemRoot"
DIAG = re.compile(
    r"^(?P<path>.+?):(?P<line>\d+):\d+: error: missing return in "
    r"(?:a function|a closure|an accessor) expected to return"
)
CASE = re.compile(r"^(?P<indent>\s*)(?:case\b.*|default\s*):\s*$")
# Statements that already transfer control, so must not gain a `return`.
CONTROL = ("return", "throw", "break", "continue", "fallthrough", "if ", "guard ",
           "switch ", "for ", "while ", "do ", "//")


def newest_log():
    logs = glob.glob(os.path.expanduser("~/legacy-ios9/logs/build-*.log"))
    return max(logs, key=os.path.getmtime) if logs else None


def diagnosed(log_path):
    out = []
    for raw in pathlib.Path(log_path).read_text(errors="replace").splitlines():
        match = DIAG.match(raw.strip())
        if not match:
            continue
        path = match.group("path")
        if path.startswith(VOLUME):
            path = path[len(VOLUME):]
        out.append((pathlib.Path(path), int(match.group("line"))))
    return sorted(set(out))


def switch_above(lines, line_index):
    """Nearest `switch` line above the reported closing brace."""
    for index in range(min(line_index, len(lines)) - 1, -1, -1):
        if re.match(r"^\s*switch\b", lines[index]):
            return index
    return None


def transform(lines, switch_index):
    """Add `return` to each arm of the switch starting at switch_index."""
    depth = 0
    changed = 0
    index = switch_index
    while index < len(lines):
        depth += lines[index].count("{") - lines[index].count("}")
        index += 1
        if depth <= 0:
            break
        match = CASE.match(lines[index - 1]) if index - 1 > switch_index else None
        if not match:
            continue
        body = index
        while body < len(lines) and not lines[body].strip():
            body += 1
        if body >= len(lines):
            continue
        text = lines[body]
        stripped = text.strip()
        if not stripped or stripped.startswith(CONTROL) or CASE.match(text):
            continue
        indent = len(text) - len(text.lstrip())
        lines[body] = text[:indent] + "return " + text[indent:]
        changed += 1
    return changed


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    group = parser.add_mutually_exclusive_group(required=True)
    group.add_argument("--report", action="store_true")
    group.add_argument("--check", action="store_true")
    group.add_argument("--apply", action="store_true")
    parser.add_argument("--log", default=None)
    args = parser.parse_args()

    log_path = args.log or newest_log()
    if not log_path:
        print("no build log found; run build.sh first", file=sys.stderr)
        return 2

    sites = diagnosed(log_path)
    for path, line in sites:
        print(f"  {path.relative_to(REPO)}:{line}")
    print(f"{len(sites)} switch expression(s) reported by the compiler")
    if args.check:
        return 1 if sites else 0
    if not args.apply:
        return 0

    total = 0
    by_file = {}
    for path, line in sites:
        by_file.setdefault(path, []).append(line)
    for path, report_lines in by_file.items():
        lines = path.read_text().splitlines(keepends=True)
        # Descending, so earlier insertions never shift a later report line.
        for line in sorted(set(report_lines), reverse=True):
            switch_index = switch_above(lines, line)
            if switch_index is None:
                print(f"  no switch above {path.name}:{line}", file=sys.stderr)
                continue
            total += transform(lines, switch_index)
        path.write_text("".join(lines))
    print(f"{total} arm(s) given an explicit return")
    return 0


if __name__ == "__main__":
    sys.exit(main())

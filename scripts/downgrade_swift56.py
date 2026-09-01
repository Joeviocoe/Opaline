#!/usr/bin/env python3
"""Expand Swift 5.7 shorthand optional bindings into the Swift 5.6 long form.

    if let x {            ->  if let x = x {
    guard let self else   ->  guard let self = self else
    if let a, let b = c {  ->  if let a = a, let b = c {

Why: Swift 5.6.1 (Xcode 13.4.1) is the newest compiler that emits
armv7-apple-ios, and it cannot *parse* the shorthand form.  `#if` is no help --
Swift parses inactive branches too -- so the legacy branch carries a mechanical
rewrite that is re-applied after every merge from upstream.

Idempotent by construction: a binding that already has `=` is skipped, so
running twice is a no-op.  That is what makes the merge ritual safe:

    git merge upstream  ->  take upstream's side on conflict
                        ->  re-run this script  ->  commit

Correctness rests on a Swift lexer (below) that masks out comments and string
literals before any pattern matching.  That is not optional: WebViewHLSSolverJS
.swift is 158 KB of minified JavaScript inside one string literal, and it
contains `let x,` sequences that a naive regex would happily corrupt.
"""

import argparse
import re
import sys
from pathlib import Path

ROOTS = ("Opaline", "OpalineOpenIn")


def code_mask(src: str) -> bytearray:
    """Return a mask over `src`: 1 where the byte is code, 0 in a comment or
    string literal.  Handles nested block comments, raw strings (#"..."#),
    multi-line strings, and string interpolation (whose contents are code)."""
    n = len(src)
    mask = bytearray(b"\x01" * n)
    stack = []  # ('string', hashes, multiline) | ('interp', paren_depth)
    quote_start = re.compile(r'(#*)("""|")')
    i = 0
    while i < n:
        top = stack[-1] if stack else None

        if top is not None and top[0] == "string":
            _, hashes, multi = top
            close = ('"""' if multi else '"') + "#" * hashes
            esc = "\\" + "#" * hashes
            if src.startswith(close, i):
                mask[i:i + len(close)] = b"\x00" * len(close)
                i += len(close)
                stack.pop()
                continue
            if src.startswith(esc + "(", i):
                span = len(esc) + 1
                mask[i:i + span] = b"\x00" * span
                i += span
                stack.append(("interp", 1))
                continue
            if src.startswith(esc, i) and i + len(esc) < n:
                span = len(esc) + 1
                mask[i:i + span] = b"\x00" * span
                i += span
                continue
            mask[i] = 0
            i += 1
            continue

        # --- code context (top level, or inside an interpolation) ---
        if src.startswith("//", i):
            j = src.find("\n", i)
            j = n if j < 0 else j
            mask[i:j] = b"\x00" * (j - i)
            i = j
            continue
        if src.startswith("/*", i):
            depth, j = 1, i + 2
            while j < n and depth:
                if src.startswith("/*", j):
                    depth += 1
                    j += 2
                elif src.startswith("*/", j):
                    depth -= 1
                    j += 2
                else:
                    j += 1
            mask[i:j] = b"\x00" * (j - i)
            i = j
            continue
        m = quote_start.match(src, i)
        if m:
            hashes = len(m.group(1))
            multi = m.group(2) == '"""'
            span = hashes + len(m.group(2))
            mask[i:i + span] = b"\x00" * span
            stack.append(("string", hashes, multi))
            i += span
            continue
        if top is not None and top[0] == "interp":
            c = src[i]
            if c == "(":
                stack[-1] = ("interp", top[1] + 1)
            elif c == ")":
                d = top[1] - 1
                if d == 0:
                    mask[i] = 0
                    stack.pop()
                    i += 1
                    continue
                stack[-1] = ("interp", d)
        i += 1
    return mask


KEYWORD = re.compile(r"\b(if|guard)\b")
BINDING = re.compile(r"\b(let|var)\s+(`?[A-Za-z_][A-Za-z0-9_]*`?)")
WHILE_SHORTHAND = re.compile(r"\bwhile\s+(let|var)\s+`?[A-Za-z_][A-Za-z0-9_]*`?\s*[,{]")
BRANCH_EXPR = re.compile(r"=\s*(if|switch)\b")
MAX_CONDITION = 4000  # a condition longer than this is not a condition


def condition_span(src, mask, start, kw):
    """Span of the condition following an `if`/`guard` keyword ending at
    `start`.  `if`/`while` end at `{`; `guard` ends at `else`.  Only `{` at
    paren/bracket depth zero terminates, so closures inside the condition --
    `first(where: { ... })` -- do not truncate it."""
    paren = bracket = 0
    i, limit = start, min(len(src), start + MAX_CONDITION)
    while i < limit:
        if not mask[i]:
            i += 1
            continue
        c = src[i]
        if c == "(":
            paren += 1
        elif c == ")":
            paren -= 1
        elif c == "[":
            bracket += 1
        elif c == "]":
            bracket -= 1
        elif paren <= 0 and bracket <= 0:
            if c == "{":
                return start, i
            if kw == "guard" and src.startswith("else", i):
                before_ok = i == 0 or not (src[i - 1].isalnum() or src[i - 1] == "_")
                after = i + 4
                after_ok = after >= len(src) or not (src[after].isalnum() or src[after] == "_")
                if before_ok and after_ok:
                    return start, i
        i += 1
    return None


def find_sites(src, mask):
    """Yield (insert_at, identifier) for each shorthand binding."""
    sites = []
    for kwm in KEYWORD.finditer(src):
        if not mask[kwm.start()]:
            continue
        span = condition_span(src, mask, kwm.end(), kwm.group(1))
        if span is None:
            continue
        lo, hi = span
        for b in BINDING.finditer(src, lo, hi):
            if not mask[b.start()]:
                continue
            # `case let x`, `if case let .foo(x)` -- pattern, not a binding.
            prefix = src[max(0, b.start() - 6):b.start()]
            if re.search(r"\bcase\s*$", prefix):
                continue
            ident = b.group(2)
            j = b.end()
            while j < hi and src[j] in " \t\n\r":
                j += 1
            if j >= hi:
                nxt = ""
            elif src.startswith("else", j):
                nxt = "else"
            else:
                nxt = src[j]
            if nxt in (",", "{", "", "else"):
                sites.append((b.end(), ident))
            # `=`  -> already long form;  `:` -> annotated, so `=` follows.
    return sites


def process(path, apply):
    src = path.read_text(encoding="utf-8")
    mask = code_mask(src)
    sites = find_sites(src, mask)
    warnings = []
    for m in WHILE_SHORTHAND.finditer(src):
        if mask[m.start()]:
            warnings.append((m.start(), "while-let shorthand: rewrite by hand"))
    for m in BRANCH_EXPR.finditer(src):
        if mask[m.start()]:
            warnings.append((m.start(), f"{m.group(1)}-expression (Swift 5.9): rewrite by hand"))
    if apply and sites:
        out = src
        for at, ident in sorted(sites, reverse=True):
            out = out[:at] + f" = {ident}" + out[at:]
        path.write_text(out, encoding="utf-8")
    return sites, warnings, src


def line_of(src, off):
    return src.count("\n", 0, off) + 1


def main():
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    g = ap.add_mutually_exclusive_group(required=True)
    g.add_argument("--report", action="store_true", help="list every site")
    g.add_argument("--check", action="store_true", help="exit 1 if any remain")
    g.add_argument("--apply", action="store_true", help="rewrite in place")
    ap.add_argument("--root", default=".", help="repository root")
    args = ap.parse_args()

    root = Path(args.root).resolve()
    files = sorted(p for r in ROOTS for p in (root / r).rglob("*.swift"))
    total = touched = 0
    all_warnings = []
    for path in files:
        sites, warnings, src = process(path, args.apply)
        rel = path.relative_to(root)
        for off, msg in warnings:
            all_warnings.append(f"{rel}:{line_of(src, off)}: {msg}")
        if not sites:
            continue
        total += len(sites)
        touched += 1
        if args.report:
            for at, ident in sites:
                print(f"{rel}:{line_of(src, at)}: let {ident} -> let {ident} = {ident}")

    verb = "rewrote" if args.apply else "found"
    print(f"\n{verb} {total} shorthand binding(s) in {touched} file(s) "
          f"of {len(files)} scanned", file=sys.stderr)
    if all_warnings:
        print("\nmanual attention required:", file=sys.stderr)
        for w in all_warnings:
            print(f"  {w}", file=sys.stderr)
    if args.check and total:
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())

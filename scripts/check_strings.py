#!/usr/bin/env python3
"""Validate translation files against the English source of truth.

For every `Opaline/xx.lproj/Localizable.strings` (xx != en):
  - unknown keys (not present in en)          -> ERROR
  - format-placeholder mismatch vs en         -> ERROR
  - duplicate keys within one file            -> ERROR
  - missing keys (present in en, absent here) -> warning only
    (.strings falls back to English at runtime, partial translations ship)

Exit code 1 on any error. Run: python3 Scripts/check_strings.py
"""
import glob
import os
import re
import sys

ROOT = os.path.join(os.path.dirname(__file__), "..", "Opaline")
PAIR_RE = re.compile(r'^"((?:[^"\\]|\\.)+)"\s*=\s*"((?:[^"\\]|\\.)*)"\s*;\s*$')
PLACEHOLDER_RE = re.compile(r"%(?:\d+\$)?[@dDuUxXoOfeEgGcCsSaAF]|%%")


def parse(path):
    pairs, dupes, broken = {}, [], []
    for num, line in enumerate(open(path, encoding="utf-8"), 1):
        stripped = line.strip()
        match = PAIR_RE.match(stripped)
        if not match:
            # a line that LOOKS like a pair but fails the strict regex has
            # an unescaped quote or missing semicolon (common LLM output bug)
            if stripped.startswith('"') and '" = "' in stripped:
                broken.append(num)
            continue
        key, value = match.group(1), match.group(2)
        if key in pairs:
            dupes.append(key)
        pairs[key] = value
    return pairs, dupes, broken


def placeholders(value):
    return sorted(p for p in PLACEHOLDER_RE.findall(value) if p != "%%")


def main():
    en, en_dupes, en_broken = parse(os.path.join(ROOT, "en.lproj", "Localizable.strings"))
    errors = [f"en.lproj: duplicate key '{k}'" for k in en_dupes]
    errors += [f"en.lproj: malformed line {n}" for n in en_broken]
    warnings = []
    for path in sorted(glob.glob(os.path.join(ROOT, "*.lproj", "Localizable.strings"))):
        lang = os.path.basename(os.path.dirname(path))
        if lang == "en.lproj":
            continue
        loc, dupes, broken = parse(path)
        errors += [f"{lang}: duplicate key '{k}'" for k in dupes]
        errors += [f"{lang}: malformed line {n} (unescaped quote?)" for n in broken]
        for key, value in loc.items():
            if key not in en:
                errors.append(f"{lang}: unknown key '{key}'")
            elif placeholders(value) != placeholders(en[key]):
                errors.append(
                    f"{lang}: placeholder mismatch in '{key}': "
                    f"{placeholders(value)} vs en {placeholders(en[key])}"
                )
        missing = sorted(set(en) - set(loc))
        if missing:
            warnings.append(f"{lang}: {len(missing)} missing keys (fall back to English)")
        print(f"{lang}: {len(loc)}/{len(en)} keys")
    for warning in warnings:
        print(f"warning: {warning}")
    for error in errors:
        print(f"ERROR: {error}", file=sys.stderr)
    return 1 if errors else 0


if __name__ == "__main__":
    sys.exit(main())

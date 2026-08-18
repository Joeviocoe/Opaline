#!/bin/bash
# Runs the YouTubeLinkParser checks against the shipping parser source.
# Usage: ./scripts/check_youtube_link_parser.sh
set -e
ROOT=$(cd "$(dirname "$0")/.." && pwd)
TMP=$(mktemp -d)
cat "$ROOT/Opaline/Core/Common/YouTubeLinkParser.swift" \
    "$ROOT/scripts/youtube_link_parser_checks.swift" > "$TMP/main.swift"
swift "$TMP/main.swift"
rm -rf "$TMP"

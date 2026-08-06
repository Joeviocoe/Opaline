#!/usr/bin/env python3
"""Patch source/apps.json for a release.

The source is served raw from main, so this must only land on main after the
release asset is actually downloadable (i.e. the GitHub release is published).
Used by make_ipa.sh locally and by .github/workflows/publish-source.yml.
"""
import argparse
import json
import re
from pathlib import Path

DEFAULT_NOTES = "See release notes on GitHub"
DEFAULT_CAPTION = "Update available — see what's new."
MIN_OS_VERSION = "12.0"
TINT_COLOR = "FF0000"


def news_caption(notes):
    """First changelog bullet, de-markdowned and clipped — the news card
    shows one line, the full notes live in the version description."""
    for line in notes.splitlines():
        line = line.strip()
        if line.startswith(("- ", "* ")):
            text = re.sub(r"\*\*(.+?)\*\*", r"\1", line[2:]).strip()
            text = re.sub(r"\s*\(#\d+.*?\)", "", text)
            if len(text) > 120:
                text = text[:117].rstrip() + "…"
            return text
    return DEFAULT_CAPTION


def release_url(download_url, version):
    """…/releases/download/<tag>/file.ipa → …/releases/tag/<tag>."""
    match = re.match(r"(.+)/releases/download/([^/]+)/", download_url)
    if match:
        return f"{match.group(1)}/releases/tag/{match.group(2)}"
    return download_url


def news_title(version, release_title):
    """The GitHub release title, prefixed with the app name (and the
    version, when the author included neither); bare/empty titles fall
    back to 'Opaline <version>'."""
    title = (release_title or "").strip()
    if not title or title == version:
        return f"Opaline {version}"
    # "ytlite" stays accepted alongside the current name so that releases
    # tagged before the rename still pass through unprefixed.
    if title.lower().startswith(("opaline", "ytlite")):
        return title
    if title.startswith(version):
        return f"Opaline {title}"
    return f"Opaline {version} — {title}"


def prepend_news(data, app, args, notes):
    entry = {
        "title": news_title(args.version, args.release_title),
        "identifier": f"release-{args.version}",
        "caption": news_caption(notes),
        "date": args.date,
        "tintColor": TINT_COLOR,
        "appID": app["bundleIdentifier"],
        "url": release_url(args.download_url, args.version),
    }
    older = [
        n for n in data.get("news", [])
        if n.get("identifier") != entry["identifier"]
    ]
    data["news"] = [entry] + older


def main():
    parser = argparse.ArgumentParser(description="Update the AltStore/SideStore source")
    parser.add_argument("--version", required=True)
    parser.add_argument("--download-url", required=True)
    parser.add_argument("--size", type=int, required=True, help="IPA size in bytes")
    parser.add_argument("--date", required=True, help="ISO 8601, e.g. 2026-07-14T11:11:29Z")
    parser.add_argument("--notes-file", help="file with the changelog text")
    parser.add_argument("--release-title", help="GitHub release title for the news entry")
    parser.add_argument("--file", default="source/apps.json")
    args = parser.parse_args()

    notes = DEFAULT_NOTES
    if args.notes_file:
        text = Path(args.notes_file).read_text(encoding="utf-8").strip()
        if text:
            notes = text

    path = Path(args.file)
    data = json.loads(path.read_text(encoding="utf-8"))
    app = data["apps"][0]

    entry = {
        "version": args.version,
        "date": args.date,
        "localizedDescription": notes,
        "downloadURL": args.download_url,
        "size": args.size,
        "minOSVersion": MIN_OS_VERSION,
    }
    older = [v for v in app.get("versions", []) if v.get("version") != args.version]
    app["versions"] = [entry] + older

    # AltStore reads these root-level duplicates of the latest version entry.
    app["version"] = args.version
    app["versionDate"] = args.date
    app["versionDescription"] = notes
    app["downloadURL"] = args.download_url
    app["size"] = args.size

    prepend_news(data, app, args, notes)

    path.write_text(json.dumps(data, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
    print(f"Updated {path}: {app['name']} v{args.version} ({args.size} bytes)")


if __name__ == "__main__":
    main()

#!/usr/bin/env python3
"""Generate a static Cydia/Sileo APT repository from .deb files.

Usage:
    make_repo.py --debs DIR --out DIR [--repo-url URL]
                 [--screenshots DIR] [--changelog FILE]

Copies the debs to OUT/debs/ and writes Packages, Packages.gz, Packages.bz2,
Release, depiction.json and index.html to OUT/. Stdlib only — no dpkg/apt
tooling required.

--screenshots: directory of images to show on the Sileo package page.
--changelog: JSON Lines file, one {"tag": ..., "body": ...} object per line
(GitHub release notes; body is markdown).
"""

import argparse
import bz2
import gzip
import hashlib
import io
import json
import lzma
import shutil
import tarfile
from pathlib import Path

REPO_LABEL = "Opaline"
REPO_DESCRIPTION = "Opaline — lightweight YouTube client for iOS 12+"
ARCHITECTURES = "iphoneos-arm iphoneos-arm64"


def ar_members(data):
    """Yield (name, bytes) for each member of an ar archive."""
    if data[:8] != b"!<arch>\n":
        raise ValueError("not an ar archive")
    offset = 8
    while offset + 60 <= len(data):
        header = data[offset : offset + 60]
        name = header[:16].decode("ascii").strip().rstrip("/")
        size = int(header[48:58].decode("ascii").strip())
        body = data[offset + 60 : offset + 60 + size]
        yield name, body
        offset += 60 + size + (size % 2)  # members are 2-byte aligned


def read_control(deb_path):
    """Extract the control file text from a .deb."""
    data = deb_path.read_bytes()
    for name, body in ar_members(data):
        if name.startswith("control.tar"):
            with tarfile.open(fileobj=io.BytesIO(body), mode="r:*") as tar:
                for member in tar.getmembers():
                    if member.name.lstrip("./") == "control":
                        return tar.extractfile(member).read().decode("utf-8")
    raise ValueError(f"{deb_path.name}: no control file found")


def control_fields(control_text):
    fields = {}
    for line in control_text.splitlines():
        if line[:1].isspace() or ":" not in line:
            continue  # continuation lines of multi-line fields
        key, value = line.split(":", 1)
        fields[key] = value.strip()
    return fields


def version_key(version):
    return tuple(int(part) if part.isdigit() else 0 for part in version.split("."))


def package_stanza(deb_path, control_text, repo_url):
    data = deb_path.read_bytes()
    stanza = control_text.strip()
    # Older debs were built before these fields existed in control —
    # inject them at repo level so their Sileo pages get depictions too.
    if "SileoDepiction:" not in stanza:
        stanza += f"\nDepiction: {repo_url}"
        stanza += f"\nSileoDepiction: {repo_url}depiction.json"
    stanza += f"\nFilename: debs/{deb_path.name}"
    stanza += f"\nSize: {len(data)}"
    stanza += f"\nMD5sum: {hashlib.md5(data).hexdigest()}"
    stanza += f"\nSHA1: {hashlib.sha1(data).hexdigest()}"
    stanza += f"\nSHA256: {hashlib.sha256(data).hexdigest()}"
    return stanza + "\n"


def release_file(out_dir, index_names):
    lines = [
        f"Origin: {REPO_LABEL}",
        f"Label: {REPO_LABEL}",
        "Suite: stable",
        "Version: 1.0",
        "Codename: ios",
        f"Architectures: {ARCHITECTURES}",
        "Components: main",
        f"Description: {REPO_DESCRIPTION}",
    ]
    for field, algo in (("MD5Sum", "md5"), ("SHA256", "sha256")):
        lines.append(f"{field}:")
        for name in index_names:
            data = (out_dir / name).read_bytes()
            digest = hashlib.new(algo, data).hexdigest()
            lines.append(f" {digest} {len(data)} {name}")
    return "\n".join(lines) + "\n"


DESCRIPTION_MD = """A lightweight YouTube client for iOS 12+. No ads, no tracking, \
no dependencies.

- SponsorBlock
- Return YouTube Dislike
- Up to 1080p playback
- Background audio and Picture in Picture
- Subtitles
"""


def depiction_json(repo_url, screenshot_names, changelog):
    """Native Sileo depiction (also rendered by Zebra)."""
    details = [
        {"class": "DepictionSubheaderView", "title": "Lightweight YouTube client for iOS 12+"},
        {"class": "DepictionMarkdownView", "markdown": DESCRIPTION_MD},
    ]
    if screenshot_names:
        details.append(
            {
                "class": "DepictionScreenshotsView",
                "itemCornerRadius": 8,
                "itemSize": "{160, 348}",
                "screenshots": [
                    {
                        "url": f"{repo_url}screenshots/{name}",
                        "accessibilityText": Path(name).stem,
                    }
                    for name in screenshot_names
                ],
            }
        )
    details.append(
        {
            "class": "DepictionTableButtonView",
            "title": "GitHub",
            "action": "https://github.com/verback2308/ytlite",
            "openExternal": True,
        }
    )

    log = []
    for entry in changelog:
        log.append(
            {"class": "DepictionSubheaderView", "useBoldText": True, "title": entry["tag"]}
        )
        log.append(
            {
                "class": "DepictionMarkdownView",
                "markdown": entry["body"] or "No notes for this release.",
            }
        )
    if not log:
        log = [
            {
                "class": "DepictionMarkdownView",
                "markdown": "See [GitHub releases]"
                "(https://github.com/verback2308/ytlite/releases).",
            }
        ]

    return {
        "minVersion": "0.1",
        "class": "DepictionTabView",
        "tintColor": "#ff0000",
        "tabs": [
            {"tabname": "Details", "class": "DepictionStackView", "views": details},
            {"tabname": "Changelog", "class": "DepictionStackView", "views": log},
        ],
    }


def load_changelog(path):
    entries = []
    for line in path.read_text(encoding="utf-8").splitlines():
        if line.strip():
            entries.append(json.loads(line))
    entries.sort(key=lambda entry: version_key(entry["tag"]), reverse=True)
    return entries


ARCH_LABELS = {"iphoneos-arm": "rootful", "iphoneos-arm64": "rootless"}


def version_list_html(entries):
    """entries: list of (version, arch, filename), newest first."""
    by_version = {}
    for version, arch, filename in entries:
        by_version.setdefault(version, []).append((arch, filename))
    items = []
    for version, debs in by_version.items():
        links = " · ".join(
            f'<a href="debs/{filename}">{ARCH_LABELS.get(arch, arch)}</a>'
            for arch, filename in sorted(debs)
        )
        items.append(f"<li><b>{version}</b> — {links}</li>")
    return "\n".join(items)


def index_html(repo_url, entries):
    return f"""<!DOCTYPE html>
<html>
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>{REPO_LABEL} Repo</title>
<style>
 body {{ font-family: -apple-system, sans-serif; max-width: 600px;
        margin: 40px auto; padding: 0 16px; }}
 code {{ background: #eee; padding: 2px 6px; border-radius: 4px; }}
 a.btn {{ display: inline-block; margin: 4px 8px 4px 0; padding: 10px 16px;
         background: #d00; color: #fff; border-radius: 8px;
         text-decoration: none; }}
</style>
</head>
<body>
<h1>{REPO_LABEL} Repo</h1>
<p>{REPO_DESCRIPTION}.</p>
<p>Add <code>{repo_url}</code> to your package manager:</p>
<p>
<a class="btn" href="sileo://source/{repo_url}">Add to Sileo</a>
<a class="btn" href="zbra://sources/add/{repo_url}">Add to Zebra</a>
<a class="btn" href="cydia://url/https://cydia.saurik.com/api/share#?source={repo_url}">Add to Cydia</a>
</p>
<p>Rootful (<code>iphoneos-arm</code>) and rootless (<code>iphoneos-arm64</code>)
packages are provided. Any version below can be installed from the repo
(Sileo/Zebra: package page → version list) or downloaded directly:</p>
<ul>
{version_list_html(entries)}
</ul>
<p><a href="https://github.com/verback2308/YTLite">Project page on GitHub</a></p>
</body>
</html>
"""


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--debs", required=True, type=Path, help="directory with .deb files")
    parser.add_argument("--out", required=True, type=Path, help="output directory for the repo")
    # Must be all-lowercase: Sileo/Cydia lowercase user-entered source URLs
    # and GitHub Pages paths are case-sensitive.
    parser.add_argument("--repo-url", default="https://repo.verback2308.pp.ua/")
    parser.add_argument("--screenshots", type=Path, help="directory of package-page images")
    parser.add_argument("--changelog", type=Path, help="JSON Lines file of {tag, body}")
    args = parser.parse_args()

    debs = sorted(args.debs.glob("*.deb"))
    if not debs:
        raise SystemExit(f"no .deb files in {args.debs}")

    # Newest versions first, so both Packages and the index read top-down.
    parsed = [(deb, read_control(deb)) for deb in debs]
    parsed = [(deb, text, control_fields(text)) for deb, text in parsed]
    parsed.sort(key=lambda item: (version_key(item[2]["Version"]), item[2]["Architecture"]))
    parsed.reverse()

    debs_out = args.out / "debs"
    debs_out.mkdir(parents=True, exist_ok=True)
    for deb, _, _ in parsed:
        shutil.copy2(deb, debs_out / deb.name)

    packages = "\n".join(package_stanza(deb, text, args.repo_url) for deb, text, _ in parsed)
    packages_bytes = packages.encode("utf-8")
    (args.out / "Packages").write_bytes(packages_bytes)
    # mtime=0 keeps the .gz byte-identical across runs for the same input
    (args.out / "Packages.gz").write_bytes(gzip.compress(packages_bytes, mtime=0))
    (args.out / "Packages.bz2").write_bytes(bz2.compress(packages_bytes))
    (args.out / "Packages.xz").write_bytes(lzma.compress(packages_bytes))

    index_names = ["Packages", "Packages.gz", "Packages.bz2", "Packages.xz"]
    entries = [
        (fields["Version"], fields["Architecture"], deb.name) for deb, _, fields in parsed
    ]
    (args.out / "Release").write_text(release_file(args.out, index_names))
    (args.out / "index.html").write_text(index_html(args.repo_url, entries))

    screenshot_names = []
    if args.screenshots:
        shots_out = args.out / "screenshots"
        shots_out.mkdir(exist_ok=True)
        for image in sorted(args.screenshots.iterdir()):
            if image.suffix.lower() in (".jpeg", ".jpg", ".png"):
                shutil.copy2(image, shots_out / image.name)
                screenshot_names.append(image.name)
    changelog = load_changelog(args.changelog) if args.changelog else []
    depiction = depiction_json(args.repo_url, screenshot_names, changelog)
    (args.out / "depiction.json").write_text(json.dumps(depiction, indent=1))

    print(f"Repo written to {args.out} ({len(debs)} package(s))")


if __name__ == "__main__":
    main()

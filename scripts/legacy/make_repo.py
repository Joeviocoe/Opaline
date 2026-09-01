#!/usr/bin/env python3
"""Generate a Cydia/Sileo APT repository from a directory of .deb files.

Pure Python: parses the ar archive and the control tarball directly, so no
dpkg-scanpackages and no apt-utils.  Output is a static tree that can be
published anywhere reachable from the device -- GitHub Pages, or any host that
serves plain files.  Cydia then adds the URL as a source and installs normally,
which sidesteps sideloading and its certificate expiry entirely.

    make_repo.py --root ~/legacy-ios9/repo

Produces:
    Release            repository metadata
    Packages           control stanzas + Filename/Size/hashes
    Packages.gz        Cydia/Sileo prefer a compressed index
    Packages.bz2       Cydia (older) looks for this first
    index.html         a human landing page, so the URL is not a 404 in a browser
    debs/*.deb         unchanged
"""

import argparse
import bz2
import gzip
import hashlib
import io
import sys
import tarfile
from pathlib import Path

ORIGIN = "Opaline Legacy (iOS 9 / armv7)"


def ar_members(data: bytes):
    """Yield (name, payload) for each member of a Unix ar archive."""
    if not data.startswith(b"!<arch>\n"):
        raise ValueError("not an ar archive")
    off = 8
    while off + 60 <= len(data):
        header = data[off:off + 60]
        name = header[0:16].decode("ascii", "replace").strip()
        size = int(header[48:58].decode("ascii").strip())
        start = off + 60
        yield name.rstrip("/"), data[start:start + size]
        off = start + size + (size & 1)   # members are padded to even offsets


def control_of(deb: Path) -> dict:
    """Pull the control stanza out of a .deb, preserving field order."""
    payload = None
    for name, blob in ar_members(deb.read_bytes()):
        if name.startswith("control.tar"):
            payload = blob
            break
    if payload is None:
        raise ValueError(f"{deb.name}: no control.tar member")
    mode = "r:gz" if payload[:2] == b"\x1f\x8b" else "r:*"
    with tarfile.open(fileobj=io.BytesIO(payload), mode=mode) as tf:
        member = next(m for m in tf.getmembers()
                      if Path(m.name).name == "control")
        text = tf.extractfile(member).read().decode("utf-8")

    fields, key = {}, None
    for line in text.splitlines():
        if line.startswith((" ", "\t")) and key:      # folded continuation
            fields[key] += "\n" + line
        elif ":" in line:
            key, _, value = line.partition(":")
            key = key.strip()
            fields[key] = value.strip()
    return fields


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--root", default=str(Path.home() / "legacy-ios9/repo"))
    args = ap.parse_args()

    root = Path(args.root).expanduser()
    debs_dir = root / "debs"
    debs = sorted(debs_dir.glob("*.deb"))
    if not debs:
        print(f"no .deb files in {debs_dir}", file=sys.stderr)
        return 1

    stanzas = []
    for deb in debs:
        raw = deb.read_bytes()
        fields = control_of(deb)
        fields["Filename"] = f"./debs/{deb.name}"
        fields["Size"] = str(len(raw))
        fields["MD5sum"] = hashlib.md5(raw).hexdigest()     # Cydia needs this
        fields["SHA1"] = hashlib.sha1(raw).hexdigest()
        fields["SHA256"] = hashlib.sha256(raw).hexdigest()  # Sileo prefers it
        stanzas.append("\n".join(f"{k}: {v}" for k, v in fields.items()))
        print(f"  {fields['Package']} {fields['Version']} "
              f"({fields['Architecture']}, {len(raw):,} B)")

    packages = ("\n\n".join(stanzas) + "\n").encode("utf-8")
    (root / "Packages").write_bytes(packages)
    (root / "Packages.gz").write_bytes(gzip.compress(packages))
    (root / "Packages.bz2").write_bytes(bz2.compress(packages))

    (root / "Release").write_text(
        f"Origin: {ORIGIN}\n"
        f"Label: {ORIGIN}\n"
        "Suite: stable\n"
        "Version: 1.0\n"
        "Codename: ios9\n"
        "Architectures: iphoneos-arm\n"
        "Components: main\n"
        "Description: Opaline built for 32-bit A5/A5X devices on iOS 9.3.5\n",
        encoding="utf-8")

    rows = "\n".join(
        f"      <li><code>{d.name}</code> &mdash; {d.stat().st_size:,} bytes</li>"
        for d in debs)
    (root / "index.html").write_text(
        "<!doctype html><meta charset=utf-8>"
        "<title>Opaline Legacy repo</title>"
        "<h1>Opaline &mdash; iOS 9 / armv7</h1>"
        "<p>Add this URL as a source in Cydia or Sileo.</p>"
        f"<ul>\n{rows}\n</ul>\n", encoding="utf-8")

    print(f"\nwrote Packages ({len(packages):,} B), Packages.gz, Packages.bz2, "
          f"Release, index.html")
    print(f"repo root: {root}")
    return 0


if __name__ == "__main__":
    sys.exit(main())

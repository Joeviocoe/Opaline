#!/usr/bin/env python3
"""Assemble Opaline.app for armv7 / iOS 9 from the build products.

Xcode normally does this, and three parts of it have to be replaced here:

* **Info.plist** is only a *partial* in the repo -- Xcode merges build settings
  and INFOPLIST_KEY_* into it.  This synthesises the full plist and overrides
  what iOS 9 needs: MinimumOSVersion, and `armv7` rather than `arm64` in
  UIRequiredDeviceCapabilities (installd rejects the bundle otherwise).

* **Launch images instead of a launch storyboard.**  `ibtool` is macOS-only, so
  the storyboard cannot be compiled.  Without *some* launch asset iOS 9
  letterboxes the app instead of running at native resolution, so plain PNGs
  under the pre-iOS-8 names are generated -- which need no tooling at all.

* **Icons.**  The catalog is flattened to loose PNGs, but iOS resolves
  `Icon-76` -> `Icon-76.png`/`Icon-76@2x.png`, so the `@1x` suffix the flattener
  emits has to go.  Alternate icons are dropped: they are iOS 10.3.
"""
import argparse
import os
import pathlib
import plistlib
import shutil
import subprocess
import sys

REPO = pathlib.Path(__file__).resolve().parents[2]
BUNDLE_ID = "com.verback.YTLite"
# Portrait first; iOS matches on pixel size, and these are the pre-iOS-8 names
# that need no storyboard and no ibtool.
LAUNCH_IMAGES = {
    "Default-Portrait@2x~ipad.png": (1536, 2048),
    "Default-Landscape@2x~ipad.png": (2048, 1536),
    "Default-Portrait~ipad.png": (768, 1024),
    "Default-Landscape~ipad.png": (1024, 768),
}


def marketing_version():
    pbx = (REPO / "Opaline.xcodeproj/project.pbxproj").read_text()
    for line in pbx.splitlines():
        if "MARKETING_VERSION = " in line:
            return line.split("= ")[1].strip().rstrip(";")
    return "1.11.0"


def build_plist(app, version):
    partial = plistlib.load((REPO / "Opaline/Info.plist").open("rb"))
    # $(VAR) substitutions Xcode would have made; none of them are needed here,
    # and a literal "$(APP_MANIFEST_URL)" in the bundle is worse than absence.
    partial = {k: v for k, v in partial.items() if not (isinstance(v, str) and v.startswith("$("))}
    # Alternate icons are iOS 10.3; the compat layer already reports them
    # unsupported, so the keys would only mislead.
    partial.pop("CFBundleIcons", None)
    partial.pop("CFBundleIcons~ipad", None)

    # Base names only: iOS resolves "Icon-76" to Icon-76.png / Icon-76@2x.png,
    # so the suffix must come off as well as the scale, or the same icon is
    # listed twice under two spellings.
    icons = sorted({
        p.stem.split("@")[0]
        for p in app.iterdir()
        if p.name.startswith("Icon-") and p.suffix == ".png"
    })
    plist = {
        "CFBundleExecutable": "Opaline",
        "CFBundleIdentifier": BUNDLE_ID,
        "CFBundleName": "Opaline",
        "CFBundleDisplayName": "Opaline",
        "CFBundlePackageType": "APPL",
        "CFBundleSignature": "????",
        "CFBundleShortVersionString": version,
        "CFBundleVersion": version,
        "CFBundleInfoDictionaryVersion": "6.0",
        "CFBundleSupportedPlatforms": ["iPhoneOS"],
        "CFBundleIconFiles": icons,
        "LSRequiresIPhoneOS": True,
        "MinimumOSVersion": "9.3",
        "UIDeviceFamily": [1, 2],
        # armv7, never arm64: installd rejects a bundle whose required
        # capabilities the device cannot meet.
        "UIRequiredDeviceCapabilities": ["armv7"],
        "UISupportedInterfaceOrientations": [
            "UIInterfaceOrientationPortrait",
            "UIInterfaceOrientationPortraitUpsideDown",
            "UIInterfaceOrientationLandscapeLeft",
            "UIInterfaceOrientationLandscapeRight",
        ],
        "UIStatusBarStyle": "UIStatusBarStyleLightContent",
        "UIViewControllerBasedStatusBarAppearance": True,
        "UIPrerenderedIcon": False,
    }
    plist.update(partial)
    with (app / "Info.plist").open("wb") as handle:
        plistlib.dump(plist, handle)
    return icons


def normalise_icons(app):
    """`Icon-76@1x.png` -> `Icon-76.png`, which is what iOS looks for."""
    for path in list(app.iterdir()):
        if path.name.startswith("Icon-") and "@1x" in path.name:
            path.rename(app / path.name.replace("@1x", ""))


def make_launch_images(app):
    try:
        from PIL import Image
    except ImportError:
        print("  Pillow missing; skipping launch images (app will letterbox)", file=sys.stderr)
        return 0
    # The splash screen's own background, so the handoff is not a flash.
    for name, size in LAUNCH_IMAGES.items():
        Image.new("RGB", size, (0, 0, 0)).save(app / name)
    return len(LAUNCH_IMAGES)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--build", default=os.path.expanduser("~/legacy-ios9/build"))
    parser.add_argument("--runtime", default=os.path.expanduser(
        "~/legacy-ios9/toolchain/xc12/Xcode.app/Contents/Developer/Toolchains/"
        "XcodeDefault.xctoolchain/usr/lib/swift-5.0/iphoneos"))
    args = parser.parse_args()

    build = pathlib.Path(args.build)
    app = build / "staging/Opaline.app"
    binary = build / "Opaline"
    if not binary.exists():
        print(f"no binary at {binary} -- run build.sh first", file=sys.stderr)
        return 1

    shutil.copy2(binary, app / "Opaline")
    (app / "Opaline").chmod(0o755)

    version = marketing_version()
    normalise_icons(app)
    icons = build_plist(app, version)
    launch = make_launch_images(app)

    # Only the dylibs this binary actually loads, thinned to armv7.
    frameworks = app / "Frameworks"
    frameworks.mkdir(exist_ok=True)
    count = subprocess.run(
        [str(REPO / "scripts/legacy/bundle-runtime.sh"), str(app), args.runtime],
        capture_output=True, text=True,
    )
    print(count.stdout.strip())
    if count.returncode != 0:
        print(count.stderr.strip(), file=sys.stderr)
        return 1

    print(f"  version {version}, {len(icons)} icon name(s), {launch} launch image(s)")
    total = sum(f.stat().st_size for f in app.rglob("*") if f.is_file())
    print(f"  bundle: {app}  ({total / 1024 / 1024:.1f} MB)")
    return 0


if __name__ == "__main__":
    sys.exit(main())

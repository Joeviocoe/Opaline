import UIKit

/// Asset loading that survives losing the asset catalog.
///
/// `actool` is macOS-only, so the armv7 / iOS 9 build flattens
/// `Assets.xcassets` into loose PNGs at build time. Loose files carry no
/// `template-rendering-intent`, and 30 of the 31 imagesets rely on it — without
/// it every tinted icon renders in its baked colour and `tintColor` silently
/// stops working. `scripts/legacy/flatten-assets.py` emits the catalog's
/// template names into a generated `LegacyAssetManifest`, which is consulted
/// here.
///
/// On a normal build this is a straight passthrough: the catalog still carries
/// the intent, so the `#if` body is inactive. Swift does not type-check
/// inactive branches, which is why the generated manifest need not exist there.
enum LegacyAssets {
    static func image(_ name: String) -> UIImage? {
        guard let image = UIImage(named: name) else {
            return nil
        }
        #if LEGACY_IOS9
        if LegacyAssetManifest.templateNames.contains(name) {
            return image.withRenderingMode(.alwaysTemplate)
        }
        #endif
        return image
    }
}

import UIKit

/// Renders letter-on-color fallback avatars for channels and
/// comment authors that have no avatar image.
enum MonogramAvatar {
    private static let palette: [UIColor] = [
        UIColor(red: 0.91, green: 0.30, blue: 0.24, alpha: 1), // red
        UIColor(red: 0.86, green: 0.39, blue: 0.60, alpha: 1), // pink
        UIColor(red: 0.61, green: 0.35, blue: 0.71, alpha: 1), // purple
        UIColor(red: 0.40, green: 0.42, blue: 0.78, alpha: 1), // indigo
        UIColor(red: 0.20, green: 0.51, blue: 0.90, alpha: 1), // blue
        UIColor(red: 0.00, green: 0.59, blue: 0.65, alpha: 1), // teal
        UIColor(red: 0.15, green: 0.62, blue: 0.35, alpha: 1), // green
        UIColor(red: 0.94, green: 0.54, blue: 0.09, alpha: 1), // orange
        UIColor(red: 0.75, green: 0.42, blue: 0.27, alpha: 1), // brown
        UIColor(red: 0.42, green: 0.51, blue: 0.58, alpha: 1) // blue gray
    ]

    // ponytail: main-thread-only cache (no lock) — MonogramAvatar.image is
    // always called from UIView setup (ThumbnailImageView.setAvatar), never
    // off-thread. Add an NSLock if a background caller shows up.
    // swiftlint:disable:next legacy_objc_type
    private static let cache = NSCache<NSString, UIImage>()

    static func color(for name: String) -> UIColor {
        palette[Int(fnv1a(name) % UInt64(palette.count))]
    }

    static func letter(for name: String) -> String {
        let letters = CharacterSet.alphanumerics
        for scalar in name.unicodeScalars where letters.contains(scalar) {
            return String(scalar).uppercased()
        }
        let trimmed = name.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        return trimmed.first.map(String.init) ?? "?"
    }

    /// Output is a pure function of `name` (letter + color) and `side`.
    /// Main-thread only — see cache note above.
    static func image(for name: String, side: CGFloat = 96) -> UIImage {
        // swiftlint:disable:next legacy_objc_type
        let key = "\(name)-\(side)" as NSString
        if let cached = cache.object(forKey: key) {
            return cached
        }
        let image = renderImage(for: name, side: side)
        cache.setObject(image, forKey: key)
        return image
    }

    private static func renderImage(for name: String, side: CGFloat) -> UIImage {
        let size = CGSize(width: side, height: side)
        let text = NSAttributedString(
            string: letter(for: name),
            attributes: [
                .font: UIFont.systemFont(
                    ofSize: side * 0.42,
                    weight: .semibold
                ),
                .foregroundColor: UIColor.white
            ]
        )
        return UIGraphicsImageRenderer(size: size).image { ctx in
            color(for: name).setFill()
            ctx.fill(CGRect(origin: .zero, size: size))
            let textSize = text.size()
            text.draw(
                at: CGPoint(
                    x: (side - textSize.width) / 2,
                    y: (side - textSize.height) / 2
                )
            )
        }
    }

    /// Stable across launches — `String.hashValue` is seeded
    /// per process, which would reshuffle colors on every run.
    private static func fnv1a(_ string: String) -> UInt64 {
        var hash: UInt64 = 0xCBF2_9CE4_8422_2325
        for byte in string.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 0x100_0000_01B3
        }
        return hash
    }
}

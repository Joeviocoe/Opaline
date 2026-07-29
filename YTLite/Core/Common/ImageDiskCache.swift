import UIKit

/// Type-safe wrapper around NSCache to avoid legacy_objc_type.
final class ImageMemoryCache {
    // swiftlint:disable:next legacy_objc_type
    private let backing = NSCache<NSString, UIImage>()

    init() {
        backing.countLimit = 300
        backing.totalCostLimit = 64 * 1_024 * 1_024
    }

    func object(forKey key: String) -> UIImage? {
        backing.object(forKey: key as NSString) // swiftlint:disable:this legacy_objc_type
    }

    func setObject(_ image: UIImage, forKey key: String, cost: Int) {
        backing.setObject(
            image,
            forKey: key as NSString, // swiftlint:disable:this legacy_objc_type
            cost: cost
        )
    }

    func removeAll() {
        backing.removeAllObjects()
    }

    func remove(url key: String) {
        backing.removeObject(forKey: key as NSString) // swiftlint:disable:this legacy_objc_type
    }
}

final class ImageDiskCache {
    private let fm = FileManager.default
    private let cacheDir: URL

    private var ttl: TimeInterval {
        let days = UserDefaults.standard.object(
            forKey: UserDefaultsKeys.Cache.imageCacheDays
        ) as? Int ?? 7
        return TimeInterval(days) * 60 * 60 * 24
    }

    init() {
        let caches = fm.urls(
            for: .cachesDirectory,
            in: .userDomainMask
        ).first ?? URL(fileURLWithPath: NSTemporaryDirectory())
        cacheDir = caches.appendingPathComponent(
            "ImageDiskCache",
            isDirectory: true
        )
        try? fm.createDirectory(
            at: cacheDir,
            withIntermediateDirectories: true,
            attributes: nil
        )
    }

    func fileURL(for url: URL) -> URL? {
        let fileURL = cacheDir.appendingPathComponent(
            cacheKey(for: url)
        )
        guard let attrs = try? fm.attributesOfItem(
            atPath: fileURL.path
        ),
            let modifiedAt = attrs[.modificationDate] as? Date
        else { return nil }
        if Date().timeIntervalSince(modifiedAt) > ttl {
            AppLog.img("disk expired \(url.absoluteString)")
            try? fm.removeItem(at: fileURL)
            return nil
        }
        return fileURL
    }

    func store(data: Data, for url: URL) {
        let fileURL = cacheDir.appendingPathComponent(
            cacheKey(for: url)
        )
        // Background fetch runs while the device is locked; the default
        // `.complete` protection would make this write fail there and
        // lose the entry.
        try? data.write(
            to: fileURL,
            options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication]
        )
    }

    func clear() {
        try? fm.removeItem(at: cacheDir)
        try? fm.createDirectory(
            at: cacheDir,
            withIntermediateDirectories: true,
            attributes: nil
        )
    }

    func remove(url: String) {
        guard let urlObj = URL(string: url) else {
            return
        }
        let fileURL = cacheDir.appendingPathComponent(
            cacheKey(for: urlObj)
        )
        try? fm.removeItem(at: fileURL)
    }

    private func cacheKey(for url: URL) -> String {
        "\(fnv1a64Hex(for: url.absoluteString)).img"
    }

    private func fnv1a64Hex(for string: String) -> String {
        let offsetBasis: UInt64 = 0xCBF2_9CE4_8422_2325
        let prime: UInt64 = 0x0000_0100_0000_01B3
        let hash = string.utf8.reduce(offsetBasis) { partial, byte in
            (partial ^ UInt64(byte)) &* prime
        }
        return String(format: "%016llx", hash)
    }
}

extension UIImage {
    var memoryCost: Int {
        guard let cgImage else {
            return 0
        }
        return cgImage.bytesPerRow * cgImage.height
    }
}

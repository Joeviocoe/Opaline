import ImageIO
import UIKit

extension ThumbnailImageView {
    // MARK: - Prefetch

    /// Network fetches started by `prefetch(url:)`, keyed by cache key, so a
    /// cell that scrolls away before the fetch lands can cancel it.
    ///
    /// Started on a background queue, cancelled from the main-thread prefetch
    /// delegate, so it needs guarding. A lock rather than a hop to main: this
    /// runs once per prefetched thumbnail during scrolling, and the main
    /// thread is the resource we are trying to free.
    private static var prefetchTokens: [String: CancellationToken] = [:]
    private static let prefetchLock = NSLock()

    static func prefetch(url: URL) {
        let key = url.absoluteString
        guard cache.object(forKey: key) == nil else {
            return
        }
        DispatchQueue.global(qos: .utility).async {
            if let cached = loadFromDiskCache(
                url: url, key: key
            ) {
                return
            }
            fetchAndCache(url: url, key: key)
        }
    }

    static func cancelPrefetch(url: URL) {
        let key = url.absoluteString
        prefetchLock.lock()
        let token = prefetchTokens.removeValue(forKey: key)
        prefetchLock.unlock()
        token?.cancel()
    }

    // MARK: - Downsampling

    static func downsample(
        imageAt fileURL: URL,
        to maxPixelSize: Int
    ) -> UIImage? {
        let options: [CFString: Any] = [
            kCGImageSourceShouldCache: false
        ]
        guard let src = CGImageSourceCreateWithURL(
            fileURL as CFURL,
            options as CFDictionary
        ) else {
            return nil
        }
        return makeThumbnail(from: src, to: maxPixelSize)
    }

    static func downsample(
        data: Data,
        to maxPixelSize: Int
    ) -> UIImage? {
        let options: [CFString: Any] = [
            kCGImageSourceShouldCache: false
        ]
        guard let src = CGImageSourceCreateWithData(
            data as CFData,
            options as CFDictionary
        ) else {
            return nil
        }
        return makeThumbnail(from: src, to: maxPixelSize)
    }

    // MARK: - Private

    private static func loadFromDiskCache(
        url: URL,
        key: String
    ) -> UIImage? {
        guard cachingEnabled,
              let fileURL = diskCache.fileURL(for: url)
        else {
            return nil
        }
        guard let img = downsample(
            imageAt: fileURL,
            to: 640
        ) else {
            return nil
        }
        cache.setObject(
            img,
            forKey: key,
            cost: img.memoryCost
        )
        return img
    }

    private static func fetchAndCache(
        url: URL,
        key: String
    ) {
        let token = CancellationToken()
        prefetchLock.lock()
        prefetchTokens[key] = token
        prefetchLock.unlock()
        transport.send(
            HTTPRequest(method: .get, url: url),
            cancellationToken: token
        ) { result in
            prefetchLock.lock()
            // Only drop our own entry — a newer prefetch for the same URL
            // may already have replaced it.
            if prefetchTokens[key] === token {
                prefetchTokens[key] = nil
            }
            prefetchLock.unlock()
            guard let data = try? result.get().data else {
                return
            }
            if let img = downsample(data: data, to: 640) {
                cache.setObject(
                    img,
                    forKey: key,
                    cost: img.memoryCost
                )
            }
            if cachingEnabled {
                diskCache.store(data: data, for: url)
            }
        }
    }

    private static func makeThumbnail(
        from src: CGImageSource,
        to maxPixelSize: Int
    ) -> UIImage? {
        let opts: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize
        ]
        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(
            src, 0, opts as CFDictionary
        ) else {
            return nil
        }
        return UIImage(cgImage: cgImage)
    }
}

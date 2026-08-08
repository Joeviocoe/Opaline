import UIKit

class ThumbnailImageView: UIImageView {
    static let cache = ImageMemoryCache()
    static let diskCache = ImageDiskCache()
    /// Injectable transport for image fetches (media plane, undecorated).
    static var transport: HTTPTransport = ServiceContainer.mediaTransport

    /// Maximum pixel dimension for downsampling.
    /// Thumbnails get 640, avatars get 96.
    var maxPixelSize: Int = 640

    private var currentURL: URL?
    private var loadToken: CancellationToken?
    private var fallbackImage: UIImage?
    private var isShowingFallback = false

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = ThemeManager.shared.thumbnailPlaceholder
        contentMode = .scaleAspectFill
        clipsToBounds = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    func setImage(url: URL, fallback: UIImage? = nil) {
        fallbackImage = fallback
        // Deliberately keyed on content, not just the URL: callers clear
        // `image` and then re-set the same URL to force a reload (see
        // `ChannelAvatarView.configure`). Skipping on a URL match alone left
        // those views permanently blank.
        let hasContent = (image != nil && !isShowingFallback)
            || loadToken != nil
        if currentURL == url, hasContent {
            return
        }
        loadToken?.cancel()
        loadToken = nil
        currentURL = url
        if let fallback {
            image = fallback
            isShowingFallback = true
        }
        loadFromMemoryOrDisk(url: url)
    }

    private func loadFromMemoryOrDisk(url: URL) {
        let key = url.absoluteString
        if let cached = ThumbnailImageView.cache.object(
            forKey: key
        ) {
            Self.logLoad("mem", since: nil, url: url)
            image = cached
            isShowingFallback = false
            loadToken = nil
            return
        }
        ThumbnailImageView.decodeQueue.async { [weak self] in
            guard let self,
                  currentURL == url
            else {
                return
            }
            loadFromDiskOrNetwork(
                url: url, cacheKey: key
            )
        }
    }

    private func loadFromDiskOrNetwork(
        url: URL,
        cacheKey: String
    ) {
        if ThumbnailImageView.cachingEnabled,
           let fileURL = ThumbnailImageView.diskCache
               .fileURL(for: url) {
            handleDiskHit(
                url: url,
                fileURL: fileURL,
                cacheKey: cacheKey
            )
            return
        }
        clearImageOnMain(url: url)
        fetchFromNetwork(url: url, cacheKey: cacheKey)
    }

    private func handleDiskHit(
        url: URL,
        fileURL: URL,
        cacheKey: String
    ) {
        let maxSz = maxPixelSize
        let t0 = Date()
        guard let img = ThumbnailImageView.downsample(
            imageAt: fileURL, to: maxSz
        ) else {
            return
        }
        Self.logLoad("disk", since: t0, url: url)
        ThumbnailImageView.cache.setObject(
            img,
            forKey: cacheKey,
            cost: img.memoryCost
        )
        DispatchQueue.main.async { [weak self] in
            guard self?.currentURL == url else {
                return
            }
            self?.loadToken = nil
            self?.image = img
            self?.isShowingFallback = false
        }
    }

    /// Before a network fetch: show the fallback (if any) so a
    /// failed load leaves the monogram, not an empty view.
    private func clearImageOnMain(url: URL) {
        DispatchQueue.main.async { [weak self] in
            guard let self,
                  currentURL == url
            else {
                return
            }
            if let fallbackImage {
                image = fallbackImage
                isShowingFallback = true
            } else {
                image = nil
            }
        }
    }

    private func fetchFromNetwork(
        url: URL,
        cacheKey: String
    ) {
        let maxSz = maxPixelSize
        let token = CancellationToken()
        loadToken = token
        let t0 = Date()
        Self.transport.send(
            HTTPRequest(method: .get, url: url),
            cancellationToken: token
        ) { [weak self] result in
            Self.logLoad("net", since: t0, url: url)
            self?.handleNetworkResponse(
                data: try? result.get().data,
                url: url,
                cacheKey: cacheKey,
                maxPixelSize: maxSz
            )
        }
    }

    private func handleNetworkResponse(
        data: Data?,
        url: URL,
        cacheKey: String,
        maxPixelSize: Int
    ) {
        defer { clearTaskOnMain(url: url) }
        guard let data,
              currentURL == url
        else {
            return
        }
        // Off the transport's callback thread and onto the one decode
        // queue, so a page of arriving thumbnails can't swamp the CPU.
        ThumbnailImageView.decodeQueue.async { [weak self] in
            self?.cacheDownsampled(
                data: data,
                url: url,
                cacheKey: cacheKey,
                maxPixelSize: maxPixelSize
            )
        }
    }

    private func clearTaskOnMain(url: URL) {
        DispatchQueue.main.async { [weak self] in
            guard self?.currentURL == url else {
                return
            }
            self?.loadToken = nil
        }
    }

    private func cacheDownsampled(
        data: Data,
        url: URL,
        cacheKey: String,
        maxPixelSize: Int
    ) {
        if let img = ThumbnailImageView.downsample(
            data: data, to: maxPixelSize
        ) {
            ThumbnailImageView.cache.setObject(
                img,
                forKey: cacheKey,
                cost: img.memoryCost
            )
        }
        if ThumbnailImageView.cachingEnabled {
            ThumbnailImageView.diskCache.store(
                data: data, for: url
            )
        }
        DispatchQueue.main.async { [weak self] in
            guard let self,
                  currentURL == url,
                  let img = ThumbnailImageView.cache
                  .object(forKey: cacheKey)
            else {
                return
            }
            image = img
            isShowingFallback = false
        }
    }
}

extension ThumbnailImageView {
    static var cachingEnabled: Bool {
        UserDefaults.standard.object(
            forKey: UserDefaultsKeys.Cache.imageCacheEnabled
        ) as? Bool ?? true
    }

    static func clearCache() {
        AppLog.img("clear all")
        cache.removeAll()
        diskCache.clear()
    }

    static func invalidate(url: String) {
        cache.remove(url: url)
        diskCache.remove(url: url)
    }

    func cancel() {
        loadToken?.cancel()
        loadToken = nil
        currentURL = nil
        fallbackImage = nil
        isShowingFallback = false
        image = nil
    }

    /// Shows the avatar at `url`, using a monogram rendered from
    /// `name` while loading, on failure, and when `url` is nil.
    func setAvatar(url: URL?, name: String) {
        let monogram = MonogramAvatar.image(for: name)
        guard let url else {
            cancel()
            image = monogram
            isShowingFallback = true
            return
        }
        setImage(url: url, fallback: monogram)
    }
}

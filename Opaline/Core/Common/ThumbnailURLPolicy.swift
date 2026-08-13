import Foundation
import UIKit

/// Ceiling on how large a thumbnail is fetched and decoded. Each step maps
/// to one YouTube file (see `ThumbnailURLPolicy.stems`), so it governs bytes
/// downloaded and bytes cached alike: 1.23 MB per decoded image at 640
/// against 2.07 MB at 960, i.e. ~52 versus ~31 in the 64 MB cache.
/// The raw value is the ceiling itself, in pixels; zero defers to the device.
enum ThumbnailQuality: Int, CaseIterable {
    case auto = 0
    case low = 320
    case medium = 480
    case high = 640
    /// maxresdefault decoded at its native 1280x720 — 3.5 MB per image, so
    /// the cache holds ~18. Auto never picks this; it is an opt-in.
    case maximum = 1_280

    static var selected: ThumbnailQuality {
        get {
            let raw = UserDefaults.standard.object(
                forKey: UserDefaultsKeys.Cache.thumbnailQuality
            ) as? Int
            return raw.flatMap(ThumbnailQuality.init) ?? .auto
        }
        set {
            UserDefaults.standard.set(
                newValue.rawValue,
                forKey: UserDefaultsKeys.Cache.thumbnailQuality
            )
            NotificationCenter.default.post(
                name: .thumbnailQualityDidChange,
                object: nil
            )
        }
    }

    /// Cells are large enough everywhere that the raw step would be the
    /// heaviest one on every device, so auto grades by memory instead:
    /// 1 GB (mini 2, Air 1, 5s, 6) stays on hqdefault, 2 GB (6s, 7, Air 2,
    /// mini 4) on sddefault — those are the devices where the network, not
    /// the display, is the bottleneck — and 3 GB+ gets maxresdefault.
    /// There is no YouTube file between sd (640) and maxres (1280), so the
    /// jump is 4-5x in bytes; the middle tier picks the cheap side.
    var pixelCeiling: Int {
        guard self == .auto else {
            return rawValue
        }
        let memory = ProcessInfo.processInfo.physicalMemory
        switch memory {
        case ..<1_500_000_000:
            return ThumbnailQuality.medium.rawValue
        case ..<2_500_000_000:
            return ThumbnailQuality.high.rawValue
        default:
            return 960
        }
    }

    var displayName: String {
        let name: String
        switch self {
        case .auto:
            name = "auto"
        case .low:
            name = "low"
        case .medium:
            name = "medium"
        case .high:
            name = "high"
        case .maximum:
            name = "maximum"
        }
        return "settings.thumbnailQuality.\(name)".localized
    }
}

extension Notification.Name {
    static let thumbnailQualityDidChange = Notification.Name(
        "thumbnailQualityDidChange"
    )
}

enum ThumbnailSizing {
    static let defaultPixelSize = 640
    static let decodeSteps = [320, 480, 640, 960, 1_280]
    static let maximumPixelSize = decodeSteps.last ?? defaultPixelSize

    static func pixelSize(
        forDisplayWidth width: CGFloat,
        scale: CGFloat
    ) -> Int {
        guard width > 0 else {
            return defaultPixelSize
        }
        let pixels = Int(ceil(width * max(scale, 1)))
        let step = decodeSteps.first { $0 >= pixels } ?? maximumPixelSize
        return min(step, ThumbnailQuality.selected.pixelCeiling)
    }

    static func pixelSize(
        for collectionView: UICollectionView
    ) -> Int {
        let flow = collectionView.collectionViewLayout
            as? UICollectionViewFlowLayout
        let width = flow?.itemSize.width ?? collectionView.bounds.width
        let scale = collectionView.window?.screen.scale
            ?? UIScreen.main.scale
        return pixelSize(forDisplayWidth: width, scale: scale)
    }
}

enum ThumbnailURLPolicy {
    private static let standardStems = [
        "maxresdefault",
        "sddefault",
        "hqdefault"
    ]

    /// Cheapest stem that still fills the decode target. `aspectFill` in a
    /// 16:9 cell crops the 4:3 letterbox away, so hq carries 480x270 of
    /// content and sd 640x360; mq is 320x180, maxres 1280x720. Always asking
    /// for maxres cost 5-10x the bytes on phone-sized cells and, for the many
    /// videos that have no maxres, a serial 404 before the first usable
    /// fallback — both visible as slow-loading thumbnails.
    private static func stems(forPixelSize size: Int) -> [String] {
        switch size {
        case ..<321:
            return ["mqdefault", "hqdefault"]
        case ..<481:
            return ["hqdefault", "sddefault"]
        case ..<641:
            return ["sddefault", "hqdefault", "maxresdefault"]
        default:
            return standardStems
        }
    }

    static func candidates(
        for url: URL,
        pixelSize: Int,
        videoId: String? = nil
    ) -> [URL] {
        let names = stems(forPixelSize: pixelSize).map { "\($0).jpg" }
        if let videoId, !videoId.isEmpty {
            let canonical = names.compactMap {
                URL(string: "https://i.ytimg.com/vi/\(videoId)/\($0)")
            }
            return unique(canonical + [url])
        }
        guard isStandardYouTubeThumbnail(url) else {
            return [url]
        }
        let generated = names.compactMap {
            replacingLastPathComponent(of: url, with: $0)
        }
        return unique(generated + [url])
    }

    private static func isStandardYouTubeThumbnail(
        _ url: URL
    ) -> Bool {
        let parts = url.pathComponents
        let isVideoPath = parts.count >= 4
            && (parts[1] == "vi" || parts[1] == "vi_webp")
        return url.host == "i.ytimg.com" && isVideoPath
    }

    private static func replacingLastPathComponent(
        of url: URL,
        with filename: String
    ) -> URL? {
        guard var components = URLComponents(
            url: url,
            resolvingAgainstBaseURL: false
        ) else {
            return nil
        }
        if url.query?.contains("sqp=") == true {
            components.query = nil
        }
        let parts = url.pathComponents
        if parts.count >= 3 {
            components.path = "/vi/\(parts[2])/\(filename)"
        } else {
            components.path = url.deletingLastPathComponent()
                .appendingPathComponent(filename).path
        }
        return components.url
    }

    private static func unique(_ urls: [URL]) -> [URL] {
        var seen = Set<URL>()
        return urls.filter { seen.insert($0).inserted }
    }
}

struct ThumbnailRequest {
    let candidates: [URL]
    let maxPixelSize: Int

    var identity: String {
        "\(candidates.first?.absoluteString ?? "")#\(maxPixelSize)"
    }

    init(
        url: URL,
        maxPixelSize: Int,
        videoId: String? = nil
    ) {
        let size = min(
            max(maxPixelSize, 1),
            ThumbnailSizing.maximumPixelSize
        )
        candidates = ThumbnailURLPolicy.candidates(
            for: url,
            pixelSize: size,
            videoId: videoId
        )
        self.maxPixelSize = size
    }

    func cacheKey(for url: URL) -> String {
        "\(url.absoluteString)#\(maxPixelSize)"
    }
}

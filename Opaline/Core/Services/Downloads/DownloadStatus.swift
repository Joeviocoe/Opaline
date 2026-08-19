import Foundation

/// Where a video stands with respect to being saved. Everything that shows
/// download state — the cell badge, the action menu, the player button, the
/// Downloads list — asks this rather than piecing the answer together from
/// the store and the downloader separately.
enum DownloadStatus {
    case none
    case queued
    case running
    case ready
    case failed

    var isActive: Bool { self == .queued || self == .running }

    static func of(_ videoId: String) -> DownloadStatus {
        let downloader = VideoDownloader.shared
        if downloader.activeVideoId == videoId {
            return .running
        }
        if downloader.isQueued(videoId) {
            return .queued
        }
        if DownloadStore.isDownloaded(videoId) {
            return .ready
        }
        return DownloadStore.hasFailed(videoId) ? .failed : .none
    }
}

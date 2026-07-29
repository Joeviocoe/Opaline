import Foundation

final class PlaybackQueue {
    static let shared = PlaybackQueue()
    private(set) var videos: [Video] = []
    private(set) var playlistTitle: String?

    var hasNext: Bool {
        videos.count > 1
    }

    var currentVideo: Video? {
        videos.first
    }

    /// The upcoming video without advancing — navigation syncs the queue
    /// itself via `seekTo` once the next page loads.
    var nextVideo: Video? {
        hasNext ? videos[1] : nil
    }

    private init() {}

    func setQueue(
        _ videos: [Video],
        title: String? = nil
    ) {
        self.videos = videos
        self.playlistTitle = title
    }

    /// Inserts `video` right after the currently playing item. An empty
    /// queue is seeded with `current` first so it stays at index 0 —
    /// `nextVideo`/`seekTo` both assume the playing item leads the list.
    func playNext(_ video: Video, current: Video) {
        if videos.isEmpty {
            videos = [current, video]
        } else {
            videos.insert(video, at: 1)
        }
    }

    func seekTo(videoId: String) {
        guard let idx = videos.firstIndex(
            where: { $0.id == videoId }
        ) else {
            return
        }
        if idx > 0 {
            videos.removeFirst(idx)
        }
    }

    func clear() {
        videos = []
        playlistTitle = nil
    }
}

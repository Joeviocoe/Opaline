import Foundation

/// The mix or playlist being played, as far as it has been read.
///
/// The whole list is kept, played items included, and a cursor moves through
/// it: the queue panel lists it and lets you go back into it, and repeat
/// needs a first item to return to. The watch page only ever hands over a
/// 20-item window around whatever is playing, so the list grows two ways —
/// each navigation folds in the window it arrived with, and the panel pages
/// the rest in with `continuation`.
final class PlaybackQueue {
    /// Raised on every change to the list or the cursor, so a screen showing
    /// the queue repaints without having to be the one that changed it —
    /// "Play next" comes from a menu that knows nothing about the panel.
    static let didChangeNotification = Notification.Name(
        "PlaybackQueueDidChange"
    )
    static let shared = PlaybackQueue()
    private(set) var videos: [Video] = [] {
        didSet { announce() }
    }
    /// Where in `videos` playback is; 0 on an empty queue.
    private(set) var currentIndex = 0 {
        didSet { announce() }
    }
    /// Which playlist or mix this queue is, if any — a hand-built "Play
    /// next" queue has none. Identity lives here rather than in "does the
    /// list happen to contain this video": mixes of the same artist overlap,
    /// and opening the second one used to graft itself onto the first.
    private(set) var playlistId: String?
    private(set) var playlistTitle: String?
    /// "Show more" token for the items past what is loaded, and the params
    /// that ask the server for this queue shuffled. Both come from the shelf.
    private(set) var continuation: String?
    private(set) var shuffleParams: String?
    private(set) var isShuffled = false
    /// The same queue in the order it arrived in, kept alongside the shuffled
    /// one so the toggle can put it back — including whatever was paged in
    /// while shuffle was on.
    private var plainOrder: [Video] = []
    var currentVideo: Video? {
        videos[safe: currentIndex]
    }

    /// The upcoming video without advancing — navigation syncs the cursor
    /// itself via `seekTo` once the next page loads.
    var nextVideo: Video? {
        videos[safe: currentIndex + 1]
    }

    private init() {}

    func setQueue(
        _ videos: [Video],
        playlistId: String? = nil,
        title: String? = nil,
        continuation: String? = nil,
        shuffleParams: String? = nil
    ) {
        self.videos = videos
        plainOrder = videos
        isShuffled = false
        self.playlistId = playlistId
        self.playlistTitle = title
        self.continuation = continuation
        self.shuffleParams = shuffleParams
        currentIndex = 0
    }

    /// Shuffles what has not played yet, leaving the cursor where it is.
    /// Reaches only as far as the queue has been loaded — the server's own
    /// shuffle covers a long playlist whole, so it is preferred where the
    /// shelf offers one.
    func shuffleRemaining() {
        isShuffled = true
        let head = videos.prefix(currentIndex + 1)
        let tail = videos.dropFirst(currentIndex + 1).shuffled()
        videos = Array(head) + tail
    }

    /// A whole-playlist order from the server. The plain order is left as it
    /// was, so turning shuffle off still comes back to it.
    func applyShuffledOrder(
        _ shuffled: [Video],
        continuation: String?
    ) {
        let playing = currentVideo?.id
        isShuffled = true
        videos = shuffled
        self.continuation = continuation
        if let playing {
            seekTo(videoId: playing)
        }
    }

    /// Back to the order the queue arrived in, cursor still on what plays.
    func unshuffle() {
        let playing = currentVideo?.id
        isShuffled = false
        videos = plainOrder
        if let playing {
            seekTo(videoId: playing)
        }
    }

    /// Drops a queued video. What is playing stays: removing it would be a
    /// skip wearing a delete button's clothes.
    func remove(videoId: String) {
        guard let idx = videos.firstIndex(where: { $0.id == videoId }),
              idx != currentIndex
        else {
            return
        }
        plainOrder.removeAll { $0.id == videoId }
        videos.remove(at: idx)
        if idx < currentIndex {
            currentIndex -= 1
        }
    }

    /// Folds a window of the same queue in, ignoring what it already holds.
    /// The token is left alone: a watch page carries one for the end of
    /// *its* window, which the panel may already have paged past.
    func append(_ more: [Video]) {
        let known = Set(videos.map(\.id))
        let fresh = more.filter { !known.contains($0.id) }
        plainOrder += fresh
        // Shuffled, what arrives later has to be shuffled in too — otherwise
        // a shuffled queue grows a tail in perfect running order.
        videos += isShuffled ? fresh.shuffled() : fresh
    }

    /// A "Show more" page, which does move the token — to nil at the end of
    /// the playlist, which is what stops the panel asking for more.
    ///
    /// A mix pages by re-generating its window rather than by walking past
    /// it, so a page can arrive with nothing the queue lacks. That is as far
    /// as the mix goes; keeping its token would fetch the same 20 forever.
    func appendPage(_ page: FeedPage) {
        let before = videos.count
        append(page.videos)
        continuation = videos.count > before
            ? page.continuation
            : nil
    }

    /// Inserts `video` right after the currently playing item. An empty
    /// queue is seeded with `current` first so the cursor has something to
    /// point at.
    func playNext(_ video: Video, current: Video) {
        if videos.isEmpty {
            videos = [current, video]
            currentIndex = 0
        } else {
            videos.insert(video, at: currentIndex + 1)
        }
    }

    func seekTo(videoId: String) {
        guard let idx = videos.firstIndex(
            where: { $0.id == videoId }
        ) else {
            return
        }
        currentIndex = idx
    }

    private func announce() {
        NotificationCenter.default.post(
            name: Self.didChangeNotification,
            object: self
        )
    }

    func clear() {
        videos = []
        plainOrder = []
        isShuffled = false
        currentIndex = 0
        playlistId = nil
        playlistTitle = nil
        continuation = nil
        shuffleParams = nil
    }
}

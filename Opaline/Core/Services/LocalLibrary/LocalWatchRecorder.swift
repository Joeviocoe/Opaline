import Foundation

/// Records a watch into the local history once it has actually been
/// watched, and keeps the local resume position moving while it plays.
///
/// Two things it is deliberately not:
///
/// - **not `WatchtimeTracker`** — that never starts without an account,
///   because `fetchWatchtimeURLs` hard-bails to nil on a missing token. That
///   is also why resume-where-you-left-off is broken for anonymous users
///   today: `setLocalFraction` lives inside the tracker and is never
///   reached. Doing it here fixes that as a side effect.
/// - **not `VideoRouter.open`** — that fires on the tap, before a frame
///   decodes, so a mis-tap would land in history with no position at all.
final class LocalWatchRecorder {
    /// Enough that a video opened and abandoned never lands in history.
    private static let tickInterval: TimeInterval = 5
    /// Watched at 30s...
    private static let absoluteThreshold: TimeInterval = 30
    /// ...or a tenth of the way in, whichever comes first.
    private static let fractionThreshold = 0.10
    /// Under 30s there is no "a tenth of the way in" worth having, so
    /// half of it stands in.
    private static let shortVideoFraction = 0.50

    /// Provides current playback position (seconds), set by the host view
    /// controller — the same shape `WatchtimeTracker` uses.
    var timeProvider: (() -> TimeInterval)?
    var durationProvider: (() -> TimeInterval)?

    private var timer: Timer?
    /// Captured from the watch page, which is the only place the title,
    /// channel, avatar, thumbnail *and* duration are all correct — an
    /// `initialVideo` is often a deep-link stub or an RSS card with no
    /// duration.
    private var pending: Video?
    private var recordedVideoId: String?
    private let store: LocalHistoryStore

    init(store: LocalHistoryStore = .shared) {
        self.store = store
    }

    /// Called when the watch page lands. Safe to call twice (the page
    /// arrives from cache, then from the network).
    func setMetadata(from page: WatchPage) {
        var video = page.video
        if video.channelAvatarURL == nil,
           let avatarURL = page.channelInfo?.avatarURL {
            video.channelAvatarURL = avatarURL
        }
        if video.channelId == nil, let channelId = page.channelInfo?.id {
            video.channelId = channelId
        }
        pending = video
    }

    func start(videoId: String) {
        stop()
        recordedVideoId = nil
        DispatchQueue.main.async { [weak self] in
            guard let self = self else {
                return
            }
            self.timer = Timer.scheduledTimer(
                withTimeInterval: LocalWatchRecorder.tickInterval,
                repeats: true
            ) { [weak self] _ in
                self?.tick(videoId: videoId)
            }
        }
        AppLog.library("recorder started \(videoId)")
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        pending = nil
    }
}

// MARK: - Recording

private extension LocalWatchRecorder {
    func tick(videoId: String) {
        let position = timeProvider?() ?? 0
        let duration = durationProvider?() ?? 0
        guard duration > 0, position > 0 else {
            return
        }
        recordProgress(
            videoId: videoId, position: position, duration: duration
        )
        guard LocalLibrary.isActive,
              LocalLibraryPreferences.savesHistory,
              recordedVideoId != videoId
        else {
            return
        }
        guard isWatched(position: position, duration: duration) else {
            return
        }
        commit(videoId: videoId, position: position, duration: duration)
    }

    /// Mirrors the position into the shared progress store so reopening the
    /// video resumes where it left off. Only when there is no account —
    /// signed in, `WatchtimeTracker` is doing this already and two writers
    /// would fight over the same key.
    func recordProgress(
        videoId: String,
        position: TimeInterval,
        duration: TimeInterval
    ) {
        guard LocalLibrary.isActive else {
            return
        }
        WatchProgressStore.shared.setLocalFraction(
            videoId: videoId,
            fraction: min(position / duration, 1)
        )
    }

    func isWatched(
        position: TimeInterval,
        duration: TimeInterval
    ) -> Bool {
        if duration < LocalWatchRecorder.absoluteThreshold {
            return position
                >= duration * LocalWatchRecorder.shortVideoFraction
        }
        return position >= LocalWatchRecorder.absoluteThreshold
            || position >= duration * LocalWatchRecorder.fractionThreshold
    }

    func commit(
        videoId: String,
        position: TimeInterval,
        duration: TimeInterval
    ) {
        guard let video = pending, video.id == videoId else {
            AppLog.library(
                "recorder \(videoId): watched but no metadata yet"
            )
            return
        }
        recordedVideoId = videoId
        AppLog.library(
            "recorder \(videoId): watched at \(Int(position))s"
                + " of \(Int(duration))s"
        )
        store.record(LocalHistoryEntry(video: video))
    }
}

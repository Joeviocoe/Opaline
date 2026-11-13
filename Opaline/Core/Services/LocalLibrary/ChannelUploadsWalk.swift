import Foundation

/// One traversal's state. A class so each asynchronous hop mutates the same
/// walk rather than copying it forward through the closures.
final class ChannelUploadsWalk {
    var remaining: [String]
    var results: [String: [Video]] = [:]
    /// Channels whose fetch failed on the first pass. They get exactly one
    /// more attempt once the first pass is through — see `beginRetryPass`.
    var failed: [String] = []
    var isRetryPass = false
    /// Requests out on the network right now, across all lanes.
    var inFlight = 0
    let total: Int
    let includeShorts: Bool
    let started = Date()
    let completion: ([String: [Video]]) -> Void
    /// Called with everything answered so far, each time another channel
    /// comes back with videos. Only the caller that started the walk gets
    /// it; joiners wait for the result.
    let progress: (([String: [Video]]) -> Void)?
    /// Callers that joined this walk after it started.
    var waiters: [([String: [Video]]) -> Void] = []

    init(
        remaining: [String],
        total: Int,
        includeShorts: Bool,
        progress: (([String: [Video]]) -> Void)?,
        completion: @escaping ([String: [Video]]) -> Void
    ) {
        self.remaining = remaining
        self.total = total
        self.includeShorts = includeShorts
        self.progress = progress
        self.completion = completion
    }

    /// Moves the first pass's failures back onto the queue, once. Returns
    /// false when there is nothing to retry or the retry already ran.
    func beginRetryPass() -> Bool {
        guard !isRetryPass, !failed.isEmpty else {
            return false
        }
        isRetryPass = true
        remaining = failed
        failed = []
        return true
    }
}

// MARK: - Walking the list

extension LocalChannelUploads {
    /// Starts up to `maxConcurrent` lanes over the walk's queue, staggered
    /// by the request spacing so even the first requests are not a burst.
    func launchLanes(_ walk: ChannelUploadsWalk) {
        let lanes = min(LocalChannelUploads.maxConcurrent, walk.remaining.count)
        guard lanes > 0 else {
            step(walk)
            return
        }
        for lane in 0..<lanes {
            let delay = LocalChannelUploads.requestSpacing * Double(lane)
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                [weak self] in
                self?.step(walk)
            }
        }
    }

    /// One lane taking the next channel. A lane that finds the queue empty
    /// while others are still out simply ends; the last one back is the one
    /// that decides between the retry pass and finishing.
    func step(_ walk: ChannelUploadsWalk) {
        if walk.remaining.isEmpty {
            guard walk.inFlight == 0 else {
                return
            }
            if walk.beginRetryPass() {
                AppLog.library(
                    "channel uploads: retrying \(walk.remaining.count)"
                        + " that failed"
                )
                // A beat before going again. The usual cause is the walk
                // starting before Wi-Fi is up on a cold launch, and those
                // failures came back in tens of milliseconds.
                DispatchQueue.main.asyncAfter(
                    deadline: .now() + LocalChannelUploads.retryDelay
                ) { [weak self] in
                    self?.launchLanes(walk)
                }
                return
            }
            finish(walk)
            return
        }
        let channelId = walk.remaining.removeFirst()
        walk.inFlight += 1
        post(LocalChannelUploads.channelFetchDidStartNotification, channelId)
        load(
            channelId: channelId, includeShorts: walk.includeShorts
        ) { [weak self] videos in
            walk.inFlight -= 1
            if let videos = videos {
                if !videos.isEmpty {
                    walk.results[channelId] = videos
                    walk.progress?(walk.results)
                }
            } else {
                walk.failed.append(channelId)
            }
            guard let self = self else {
                return
            }
            self.post(
                LocalChannelUploads.channelFetchDidEndNotification, channelId
            )
            DispatchQueue.main.asyncAfter(
                deadline: .now() + LocalChannelUploads.requestSpacing
            ) {
                self.step(walk)
            }
        }
    }

    func finish(_ walk: ChannelUploadsWalk) {
        let ms = Int(Date().timeIntervalSince(walk.started) * 1_000)
        AppLog.library(
            "channel uploads: \(walk.results.count)/\(walk.total)"
                + " answered in \(ms)ms, \(walk.waiters.count) joined,"
                + " \(walk.failed.count) failed after retry"
        )
        walkInProgress = nil
        NotificationCenter.default.post(
            name: LocalChannelUploads.walkDidFinishNotification, object: self
        )
        walk.completion(walk.results)
        for waiter in walk.waiters {
            waiter(walk.results)
        }
        guard let queued = queuedRewalk else {
            return
        }
        queuedRewalk = nil
        fetch(
            channelIds: queued.ids,
            includeShorts: queued.includeShorts,
            completion: queued.completion
        )
    }

    private func post(_ name: Notification.Name, _ channelId: String) {
        NotificationCenter.default.post(
            name: name, object: self,
            userInfo: [LocalChannelUploads.channelIdKey: channelId]
        )
    }
}

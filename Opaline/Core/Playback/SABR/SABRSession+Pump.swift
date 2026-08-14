import Foundation

// MARK: - Fetch pump
//
// One request in flight at a time, driven by what readers are waiting for.
// Readers themselves never touch the network.

extension SABRSession {
    /// True while the stream holds less than the prefetch window ahead of the
    /// playhead — and only while the buffer has room, so prefetching cannot
    /// push memory past the ceiling.
    var shouldPrefetch: Bool {
        guard !reachedEnd, !progress.isEmpty else {
            return false
        }
        // Only bytes the player has not taken yet count towards the ceiling.
        // Counting everything held meant video — segments ten times the size
        // of audio — filled the quota on its own, the pump went quiet, and the
        // audio track stopped being fetched even though it was the one running
        // behind. That is what produced 40-second waits on audio segments.
        guard unreadBytes < Self.bufferLimit * 3 / 4 else {
            return false
        }
        let buffered = progress.values.map(\.bufferedMs).min() ?? 0
        return buffered - lastServedMs < Self.prefetchMs
    }

    /// Bytes buffered ahead of what has already been handed to the player.
    private var unreadBytes: Int {
        buffers.reduce(0) { total, entry in
            let read = readOffsets[entry.key] ?? entry.value.start
            return total + max(0, Int(entry.value.end - max(read, entry.value.start)))
        }
    }

    /// Keeps exactly one request in flight while there is something to fetch:
    /// either a read is waiting, or the buffer has run down to less than the
    /// prefetch window ahead of the playhead.
    func pump() {
        guard !inFlight, !waiting.isEmpty || shouldPrefetch else {
            return
        }
        // Follow whoever is furthest behind, so the stream advances from the
        // earliest point still needed instead of chasing the newest read. With
        // nobody waiting, keep going from where playback has got to.
        let earliest = waiting.min { $0.request.timeMs < $1.request.timeMs }
        let target = earliest?.request
            ?? SABRReadRequest(itag: video.itag, offset: 0, length: 0, timeMs: lastServedMs)
        guard let body = nextBody(for: target) else {
            AppLog.hls("sabr pump: nothing to send, end=\(reachedEnd)")
            finishWaiters(with: SABRError.stalled)
            return
        }
        inFlight = true
        send(body) { [weak self] result in
            guard let self else {
                return
            }
            self.inFlight = false
            switch result {
            case .failure(let error):
                self.finishWaiters(with: error)
            case .success:
                self.afterResponse()
            }
        }
    }

    func afterResponse() {
        serveWaiters()
        // Counts responses that brought no media at all. Keying this off
        // "nobody was served" instead would never fire during prefetch, when
        // serving nobody is the normal case.
        emptyRounds = sawMediaInLastResponse ? 0 : emptyRounds + 1
        guard emptyRounds < Self.maxEmptyRounds else {
            AppLog.hls("sabr pump: no progress in \(emptyRounds) rounds")
            finishWaiters(with: SABRError.stalled)
            return
        }
        pump()
    }

    /// Hands buffered bytes to whoever can be answered now.
    ///
    /// Collects first and mutates after: calling back into the session from
    /// inside `removeAll` is what exclusive-access enforcement traps on.
    func serveWaiters() -> Bool {
        var ready: [(waiter: Waiter, data: Data)] = []
        var stillWaiting: [Waiter] = []
        for waiter in waiting {
            if let data = buffered(
                itag: waiter.request.itag,
                offset: waiter.request.offset,
                length: waiter.request.length
            ) {
                ready.append((waiter, data))
            } else {
                stillWaiting.append(waiter)
            }
        }
        waiting = stillWaiting
        for entry in ready {
            markRead(
                itag: entry.waiter.request.itag,
                offset: entry.waiter.request.offset,
                length: entry.waiter.request.length,
                timeMs: entry.waiter.request.timeMs
            )
            entry.waiter.completion(.success(entry.data))
        }
        return !ready.isEmpty
    }

    func finishWaiters(with error: Error) {
        let pending = waiting
        waiting.removeAll()
        emptyRounds = 0
        pending.forEach { $0.completion(.failure(error)) }
    }
}

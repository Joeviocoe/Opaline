import Foundation

// MARK: - Opening a session

extension SABRSession {
    /// Opens the session and returns the init segment of each stream — the
    /// `ftyp/moov/sidx` prefix AVPlayer needs before any media.
    /// `resumeAt` starts the stream at the playhead instead of at zero —
    /// switching quality mid-video otherwise streams the opening again while
    /// the player waits for the part it is actually on.
    func start(
        resumeAt: Int = 0,
        completion: @escaping (Result<[Int: Data], Error>) -> Void
    ) {
        queue.async {
            let body = SABRRequest.startup(
                ustreamerConfig: self.ustreamerConfig,
                audio: self.audio,
                video: self.video,
                identity: self.identity
            )
            self.send(body) { [weak self] result in
                self?.opened(result, resumeAt: resumeAt, completion: completion)
            }
        }
    }

    private func opened(
        _ result: Result<Void, Error>,
        resumeAt: Int,
        completion: @escaping (Result<[Int: Data], Error>) -> Void
    ) {
        if case .failure(let error) = result {
            completion(.failure(error))
            return
        }
        let inits = initSegments
        guard inits[audio.itag] != nil, inits[video.itag] != nil else {
            completion(.failure(SABRError.noInitSegment))
            return
        }
        guard resumeAt > 0 else {
            completion(.success(inits))
            return
        }
        // Report ready on the init segments and let the reposition land in
        // the background. `moov` is all the player needs to build the item;
        // the media it asks for next parks as a waiter until the jump
        // answers. Waiting here instead put the whole jump response — six
        // megabytes — in front of the first frame. Sent before the completion
        // so it is already in flight when the first read arrives on this queue.
        jump(to: resumeAt) { [weak self] in
            self?.afterResponse()
        }
        completion(.success(inits))
    }

    /// Repositions the stream, keeping the init segments already collected.
    private func jump(to timeMs: Int, completion: @escaping () -> Void) {
        resetBuffers()
        progress.removeAll()
        lastServedMs = timeMs
        let body = SABRRequest.jump(
            ustreamerConfig: ustreamerConfig,
            audio: audio,
            video: video,
            identity: identity,
            playerMs: timeMs,
            // Segments run about five seconds; the exact figure does not
            // matter, only that it is consistent with the buffer claimed.
            sequence: max(1, timeMs / 5_000)
        )
        // Claimed as in flight so a read landing while it travels parks
        // instead of firing a second, competing request.
        inFlight = true
        send(body) { [weak self] _ in
            self?.inFlight = false
            completion()
        }
    }
}

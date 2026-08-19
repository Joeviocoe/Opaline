import Foundation

// MARK: - Riding out a network drop

extension VideoDownloader {
    /// How long to keep trying on its own before the download becomes the
    /// user's problem. A dropped connection is usually back within a minute;
    /// past that the phone is somewhere without a network and retrying is
    /// just radio time spent for nothing.
    static let retryDelays: [TimeInterval] = [5, 20, 45]

    /// Schedules another attempt at the running job, resuming from what is
    /// already on disk. Returns false when the budget is spent and the job
    /// should be reported as failed.
    func retryLater(videoId: String) -> Bool {
        guard let job = jobs.first, job.video.id == videoId else {
            return false
        }
        guard job.attempt < Self.retryDelays.count else {
            AppLog.downloads("giving up on \(videoId) after \(job.attempt) retries")
            return false
        }
        let delay = Self.retryDelays[job.attempt]
        bumpAttempt()
        AppLog.downloads(
            "retrying \(videoId) in \(Int(delay))s"
                + " (attempt \(job.attempt + 1))"
        )
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            self?.resumeCurrentJob(videoId: videoId)
        }
        return true
    }

    /// The job may have been cancelled while the delay ran, and something
    /// else may be running by now — only resume if it is still the one.
    private func resumeCurrentJob(videoId: String) {
        guard let job = jobs.first, job.video.id == videoId else {
            return
        }
        cancellation = CancellationToken()
        resetProgressToDisk(videoId: videoId)
        fetchTracks(videoId: videoId, option: job.option)
    }
}

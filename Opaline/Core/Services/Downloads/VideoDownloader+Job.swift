import Foundation

// MARK: - Running one job

extension VideoDownloader {
    /// Everything already written across both parts, so a resumed job reports
    /// the progress it actually stands at rather than starting from zero.
    func bytesAlreadySaved(videoId: String) -> Int64 {
        [videoPartFile(videoId), audioPartFile(videoId)]
            .map(Self.bytesOnDisk)
            .reduce(0, +)
    }

    func videoPartFile(_ videoId: String) -> URL {
        DownloadStore.partFile(
            for: videoId, named: "video" + DownloadStore.partSuffix
        )
    }

    func audioPartFile(_ videoId: String) -> URL {
        DownloadStore.partFile(
            for: videoId, named: "audio" + DownloadStore.partSuffix
        )
    }

    func fetchTracks(videoId: String, option: DownloadOption) {
        let videoPart = videoPartFile(videoId)
        let audioPart = audioPartFile(videoId)
        download(
            from: option.video.url,
            to: videoPart,
            size: option.video.contentLength
        ) { [weak self] error in
            if let error {
                self?.fail(videoId: videoId, error: error)
                return
            }
            self?.fetchAudio(
                videoId: videoId,
                option: option,
                parts: (videoPart, audioPart)
            )
        }
    }

    private func fetchAudio(
        videoId: String,
        option: DownloadOption,
        parts: (video: URL, audio: URL)
    ) {
        download(
            from: option.audio.url,
            to: parts.audio,
            size: option.audio.contentLength
        ) { [weak self] error in
            if let error {
                self?.fail(videoId: videoId, error: error)
                return
            }
            self?.mux(videoId: videoId, option: option, parts: parts)
        }
    }

    func fail(videoId: String, error: Error) {
        let cancelled = cancellation?.isCancelled == true
        guard !cancelled else {
            DownloadStore.removeParts(for: videoId)
            finishJob(reporting: nil)
            return
        }
        AppLog.downloads("failed \(videoId): \(error)")
        guard !retryLater(videoId: videoId) else {
            return
        }
        // Only now are the parts worth dropping: a retry would have resumed
        // from them.
        DownloadStore.removeParts(for: videoId)
        DownloadStore.markFailed(videoId)
        finishJob(reporting: .failure(error))
    }
}

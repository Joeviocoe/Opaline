import Foundation

// MARK: - Everything around the video, saved with it

extension VideoDownloader {
    /// Fetched once, when the download is asked for. Whatever fails here just
    /// leaves that piece missing offline — none of it is worth failing a
    /// download over.
    func saveMetadata(for video: Video) {
        DownloadStore.save(video)
        fetchThumbnail(for: video)
        fetchPage(for: video)
        fetchSegments(for: video.id)
        fetchVotes(for: video.id)
        fetchComments(for: video.id)
    }

    private func fetchVotes(for videoId: String) {
        guard ReturnYouTubeDislikeService.enabled else {
            return
        }
        ReturnYouTubeDislikeService.shared.fetchVotes(videoId: videoId) { result in
            guard case .success(let votes) = result else {
                return
            }
            DownloadStore.saveVotes(votes, for: videoId)
        }
    }

    private func fetchPage(for video: Video) {
        apiClient.fetchWatchPage(
            video: video, cancellationToken: nil
        ) { [weak self] result in
            guard case .success(let page) = result else {
                AppLog.downloads("no watch page saved for \(video.id)")
                return
            }
            DownloadStore.savePage(page, for: video.id)
            self?.fetchAvatar(from: page, videoId: video.id)
        }
    }

    private func fetchSegments(for videoId: String) {
        guard SponsorBlockService.enabled else {
            return
        }
        SponsorBlockService.shared.fetchSegments(videoId: videoId) { result in
            guard case .success(let segments) = result, !segments.isEmpty else {
                return
            }
            DownloadStore.saveSegments(segments, for: videoId)
            AppLog.downloads("saved \(segments.count) segments for \(videoId)")
        }
    }

    private func fetchAvatar(from page: WatchPage, videoId: String) {
        guard let raw = page.channelInfo?.avatarURL ?? page.video.channelAvatarURL,
              let url = URL(string: raw) else {
            return
        }
        fetchImage(url) { data in
            DownloadStore.saveAvatar(data, for: videoId, url: url)
        }
    }

    /// The picture the offline list shows. Kept beside the video, because the
    /// image cache it also primes is purgeable and expires.
    func fetchThumbnail(for video: Video) {
        guard let url = URL(string: video.thumbnailURL) else {
            return
        }
        fetchImage(url) { data in
            DownloadStore.saveThumbnail(data, for: video)
        }
    }

    private func fetchImage(_ url: URL, then store: @escaping (Data) -> Void) {
        transport.send(
            HTTPRequest(method: .get, url: url),
            cancellationToken: nil
        ) { result in
            guard case .success(let response) = result,
                  (200...299).contains(response.status) else {
                return
            }
            store(response.data)
        }
    }
}

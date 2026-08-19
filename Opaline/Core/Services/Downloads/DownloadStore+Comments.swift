import Foundation

// MARK: - Comments as they were when the video was saved

extension DownloadStore {
    /// One fetched page and the token that asked for it, so the same paging
    /// the screen does online works from disk: the first page answers a nil
    /// continuation, and each stored token answers the page it led to.
    struct StoredComments: Codable {
        let requestedWith: String?
        let page: CommentsPage
    }

    private static let commentsFileName = "comments.json"

    static func saveComments(
        _ pages: [StoredComments],
        for videoId: String
    ) {
        guard let data = try? JSONEncoder().encode(pages) else {
            AppLog.downloads("could not encode comments for \(videoId)")
            return
        }
        let total = pages.reduce(0) { $0 + $1.page.comments.count }
        AppLog.downloads(
            "saved \(pages.count) comment pages"
                + " (\(total) threads, \(data.count / 1_024) KB) for \(videoId)"
        )
        try? data.write(to: commentsFile(for: videoId), options: .atomic)
    }

    static func comments(
        for videoId: String,
        continuation: String?
    ) -> CommentsPage? {
        guard let data = try? Data(contentsOf: commentsFile(for: videoId)),
              let pages = try? JSONDecoder().decode(
                  [StoredComments].self, from: data
              ) else {
            return nil
        }
        return pages.first { $0.requestedWith == continuation }?.page
    }

    private static func commentsFile(for videoId: String) -> URL {
        folder(for: videoId).appendingPathComponent(commentsFileName)
    }
}

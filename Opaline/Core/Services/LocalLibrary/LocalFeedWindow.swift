import Foundation

/// Decides how far back a locally assembled feed reaches.
///
/// RSS hands back roughly fifteen entries per channel with no date bound, so
/// a feed that just concatenated them would be an archive rather than a
/// feed: one dormant channel's two-year-old back catalogue would sit in the
/// middle of this week's videos.
///
/// So: the last 30 days — unless that is thinner than `minimumVideos`, in
/// which case the newest `minimumVideos` regardless of age. Somebody
/// subscribed to five quiet channels should still see something.
enum LocalFeedWindow {
    static let days = 30
    static let minimumVideos = 40

    static func apply(to dated: [(date: Date, video: Video)]) -> [Video] {
        let cutoff = Date().addingTimeInterval(
            -Double(days) * 24 * 60 * 60
        )
        let recent = dated.filter { $0.date >= cutoff }
        if recent.count >= minimumVideos {
            AppLog.library(
                "local feed window: \(recent.count) videos"
                    + " within \(days) days"
            )
            return recent.map { $0.video }
        }
        let fallback = Array(dated.prefix(minimumVideos))
        AppLog.library(
            "local feed window: only \(recent.count) within \(days)"
                + " days, taking newest \(fallback.count)"
        )
        return fallback.map { $0.video }
    }
}

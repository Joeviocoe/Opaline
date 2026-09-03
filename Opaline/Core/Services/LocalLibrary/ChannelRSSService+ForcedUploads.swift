import Foundation

// The one genuine addition to an existing protocol in this branch.
//
// `fetchRecentShorts` already takes `force:`; `fetchRecentUploads` does not,
// so pull-to-refresh on a locally assembled feed would have been a no-op for
// the full 30-minute cache TTL. Protocol requirements cannot carry default
// arguments, so the parameter has to be declared rather than defaulted —
// which is why this is a protocol change and not a call-site one.

extension ChannelRSSService {
    func fetchRecentUploads(
        channelIds: [String],
        includeShorts: Bool,
        force: Bool,
        completion: @escaping ([String: [RSSVideoEntry]]) -> Void
    ) {
        let variant: RSSFeedVariant = includeShorts ? .all : .longForm
        if force {
            queue.async { [weak self] in
                self?.invalidate(channelIds, variant: variant)
            }
        }
        fetchRecentUploads(
            channelIds: channelIds,
            includeShorts: includeShorts,
            completion: completion
        )
    }
}

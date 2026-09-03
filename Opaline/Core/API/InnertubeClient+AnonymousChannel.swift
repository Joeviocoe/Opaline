import Foundation

/// Channel browsing that needs no account.
///
/// `fetchChannelInfo` and `fetchChannelPage` both open with a `validToken`
/// guard and fail `unauthorized` without one, which is why the channel
/// screen reads "Channel unavailable" for a signed-out user. Nothing about
/// the data requires an account though — the WEB client serves a channel
/// browse anonymously, and this app already relies on that in two places:
/// `fetchWebChannelEnrichment` does exactly this request to enrich a TV
/// channel, and every `fetchChannelTab` call is anonymous already.
///
/// So this adds no new parsing: it reuses `parseChannelInfo`, which is the
/// same function the enrichment path has been running against real
/// responses all along.
protocol AnonymousChannelBrowsing: AnyObject {
    func fetchChannelInfoAnonymously(
        channelId: String,
        completion: @escaping (Result<ChannelInfo, Error>) -> Void
    )
    func fetchChannelPageAnonymously(
        channelId: String,
        completion: @escaping (Result<ChannelPage, Error>) -> Void
    )
}

extension InnertubeClient: AnonymousChannelBrowsing {
    func fetchChannelInfoAnonymously(
        channelId: String,
        completion: @escaping (Result<ChannelInfo, Error>) -> Void
    ) {
        var body = webContext
        body[JSONKey.browseId] = channelId
        execute(
            urlString: "\(baseURL)\(InnertubeEndpoint.browse)",
            body: body,
            headers: anonHeaders(),
            logTag: "channelInfoAnon(\(channelId))"
        ) { json -> ChannelInfo? in
            Self.parseChannelInfo(json, fallbackChannelId: channelId)
        } completion: { result in
            completion(result)
        }
    }

    /// The videos tab plus whatever identity could be resolved. The tab is
    /// the part that matters — a channel screen with no header is thin, but
    /// a channel screen with no videos is broken — so a failed info lookup
    /// degrades to a placeholder rather than failing the whole page.
    func fetchChannelPageAnonymously(
        channelId: String,
        completion: @escaping (Result<ChannelPage, Error>) -> Void
    ) {
        fetchChannelTab(
            channelId: channelId,
            params: ChannelTabParams.videos
        ) { [weak self] tabResult in
            guard let self = self else {
                return
            }
            switch tabResult {
            case .success(let tab):
                self.attachInfo(
                    to: tab, channelId: channelId, completion: completion
                )
            case .failure(let error):
                AppLog.channel(
                    "anon channel \(channelId): videos failed: \(error)"
                )
                completion(.failure(error))
            }
        }
    }

    private func attachInfo(
        to tab: ChannelTabPage,
        channelId: String,
        completion: @escaping (Result<ChannelPage, Error>) -> Void
    ) {
        fetchChannelInfoAnonymously(channelId: channelId) { result in
            let info: ChannelInfo
            switch result {
            case .success(let fetched):
                info = fetched
            case .failure(let error):
                AppLog.channel(
                    "anon channel \(channelId): info failed"
                        + " (\(error)) — placeholder header"
                )
                info = Self.placeholderInfo(channelId: channelId)
            }
            AppLog.channel(
                "anon channel \(channelId): '\(info.title)'"
                    + " \(tab.feedPage.videos.count) videos"
            )
            completion(
                .success(
                    ChannelPage(
                        info: info,
                        videosPage: tab.feedPage,
                        subscribeButtonText: nil,
                        isSubscribed: LocalSubscriptionStore.shared
                            .isSubscribed(channelId: channelId)
                    )
                )
            )
        }
    }

    /// Whatever is already known locally beats an empty header: a channel
    /// subscribed to on this device has its name and avatar in the store.
    private static func placeholderInfo(channelId: String) -> ChannelInfo {
        let known = LocalChannelIdentity.shared.identity(for: channelId)
        return ChannelInfo(
            id: channelId,
            title: known.title,
            avatarURL: known.avatarURL,
            subscriberCountText: nil,
            bannerURL: nil,
            isVerified: false,
            description: nil,
            contactInfo: nil,
            videoCountText: nil
        )
    }
}

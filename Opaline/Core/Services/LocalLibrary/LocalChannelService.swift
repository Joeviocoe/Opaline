import Foundation

/// Channel pages without an account.
///
/// Same decorator shape as the rest of the local library: signed in, every
/// call goes straight to the client and nothing changes. Signed out, the
/// anonymous WEB browse answers instead of the token-gated TV one, which is
/// what turns "Channel unavailable" into an actual channel.
///
/// This is the piece that closes the loop for a local library — subscribing
/// to channels you cannot then open is a strange half-feature.
final class LocalChannelService: ChannelService {
    private let inner: ChannelService
    private let anonymous: AnonymousChannelBrowsing

    init(
        wrapping inner: ChannelService,
        anonymous: AnonymousChannelBrowsing
    ) {
        self.inner = inner
        self.anonymous = anonymous
    }

    func fetchChannelInfo(
        channelId: String,
        completion: @escaping (Result<ChannelInfo, Error>) -> Void
    ) {
        guard LocalLibrary.isActive else {
            inner.fetchChannelInfo(
                channelId: channelId, completion: completion
            )
            return
        }
        anonymous.fetchChannelInfoAnonymously(
            channelId: channelId, completion: completion
        )
    }

    func fetchChannelPage(
        channelId: String,
        completion: @escaping (Result<ChannelPage, Error>) -> Void
    ) {
        guard LocalLibrary.isActive else {
            inner.fetchChannelPage(
                channelId: channelId, completion: completion
            )
            return
        }
        anonymous.fetchChannelPageAnonymously(
            channelId: channelId, completion: completion
        )
    }

    /// Enrichment merges a TV response with a WEB one. With no account
    /// there was no TV response to begin with — the anonymous page is
    /// already the WEB one — so there is nothing to enrich.
    func enrichChannelInfo(
        channelId: String,
        tvInfo: ChannelInfo,
        onEnriched: @escaping (ChannelInfo) -> Void
    ) {
        guard LocalLibrary.isActive else {
            inner.enrichChannelInfo(
                channelId: channelId,
                tvInfo: tvInfo,
                onEnriched: onEnriched
            )
            return
        }
    }
}

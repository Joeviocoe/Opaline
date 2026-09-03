import UIKit

// MARK: - Subscribe from a card
//
// The highest-leverage subscribe surface in the app, and the one that did
// not exist: the channel screen is the only other place offering it, and
// `fetchChannelInfo`/`fetchChannelPage` both hard-fail without a token — so
// with no account there was no way to subscribe to anything at all except
// from the watch screen.
//
// A card carries everything needed: `channelId`, `channelName` and
// `channelAvatarURL` are already on the `Video`, so capturing the identity
// costs nothing here.

extension VideoActionMenu {
    static func subscribeItem(
        video: Video,
        from presenter: UIViewController
    ) -> PlayerMenuItem? {
        // Only where it is the *only* way in. Signed in, a feed renderer
        // carries no subscription state, so the row could only ever say
        // "Subscribe" — wrong half the time, on a menu that already has to
        // leave room for the feedback actions. The channel and watch
        // screens both work with an account anyway.
        guard LocalLibrary.isActive,
              SubscribeAction.isAvailable,
              let channelId = video.channelId,
              !channelId.isEmpty,
              !video.channelName.isEmpty
        else {
            return nil
        }
        let isSubscribed = SubscribeAction.isSubscribed(video: video)
        let title = isSubscribed
            ? "video.menu.unsubscribeFrom".localized(with: video.channelName)
            : "video.menu.subscribeTo".localized(with: video.channelName)
        return PlayerMenuItem(
            title: title,
            iconName: isSubscribed ? "icon_minus_circle" : "icon_person_fill"
        ) {
            toggleSubscription(
                video: video,
                wasSubscribed: isSubscribed,
                from: presenter
            )
        }
    }

    private static func toggleSubscription(
        video: Video,
        wasSubscribed: Bool,
        from presenter: UIViewController
    ) {
        SubscribeAction.toggle(
            video: video,
            wasSubscribed: wasSubscribed
        ) { result in
            DispatchQueue.main.async {
                showSubscribeOutcome(
                    result,
                    channelName: video.channelName,
                    wasSubscribed: wasSubscribed,
                    from: presenter
                )
            }
        }
    }

    /// Subscribing changes nothing on the screen the menu was opened from,
    /// so without a toast a success is indistinguishable from a dead row.
    private static func showSubscribeOutcome(
        _ result: Result<Void, Error>,
        channelName: String,
        wasSubscribed: Bool,
        from presenter: UIViewController
    ) {
        switch result {
        case .success:
            let message = wasSubscribed
                ? "video.menu.unsubscribed".localized(with: channelName)
                : "video.menu.subscribed".localized(with: channelName)
            ToastView.show(message, in: presenter.view)
        case .failure(let error):
            AppLog.subscribe("menu subscribe failed: \(error)")
            showFailed(in: presenter.view)
        }
    }
}

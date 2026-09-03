import UIKit

// MARK: - Like / Dislike / Subscribe
extension WatchViewController {
    @objc
    func likeTapped() {
        guard let videoId = watchPage?.video.id else {
            return
        }
        let wasLiked = currentLikeStatus == .like
        currentLikeStatus = wasLiked ? .indifferent : .like
        // Optimistic, like the tint below: the request result arrives too
        // late to feel connected to the tap.
        if !wasLiked {
            Feedback.success()
        }
        AppLog.player(
            "like tapped: "
            + "\(wasLiked ? "removing" : "sending") like"
            + " for \(videoId)"
        )
        updateLikeDislikeUI()
        if wasLiked {
            engagementClient.removeLike(videoId: videoId) { [weak self] result in
                self?.handleLikeToggleResult(result, videoId: videoId, wasLiked: true)
            }
        } else {
            engagementClient.sendLike(videoId: videoId) { [weak self] result in
                self?.handleLikeToggleResult(result, videoId: videoId, wasLiked: false)
            }
        }
    }

    @objc
    func dislikeTapped() {
        guard let videoId = watchPage?.video.id else {
            return
        }
        let wasDisliked = currentLikeStatus == .dislike
        currentLikeStatus = wasDisliked ? .indifferent : .dislike
        AppLog.player(
            "like tapped: "
            + "\(wasDisliked ? "removing" : "sending")"
            + " dislike for \(videoId)"
        )
        updateLikeDislikeUI()
        if wasDisliked {
            engagementClient.removeLike(videoId: videoId) { [weak self] result in
                self?.handleDislikeToggleResult(result, videoId: videoId, wasDisliked: true)
            }
        } else {
            engagementClient.sendDislike(videoId: videoId) { [weak self] result in
                self?.handleDislikeToggleResult(result, videoId: videoId, wasDisliked: false)
            }
        }
    }

    // MARK: - Subscribe

    func handleSubscribeResult(
        _ result: Result<Void, Error>,
        channelId: String,
        wasSubscribed: Bool
    ) {
        subscribeButton.isEnabled = true
        switch result {
        case .success:
            let verb = wasSubscribed
                ? "unsubscribed" : "subscribed"
            AppLog.subscribe(
                "\(verb) channelId=\(channelId)"
            )
        case .failure(let error):
            let verb = wasSubscribed
                ? "unsubscribe" : "subscribe"
            AppLog.subscribe(
                "\(verb) failed channelId=\(channelId): \(error)"
            )
            isSubscribed = wasSubscribed
            subscribeButton.setTitle(
                wasSubscribed
                    ? "common.subscribed".localized
                    : "common.subscribe".localized,
                for: .normal
            )
            applyTheme()
        }
    }

    private func subscribeHandler(
        channelId: String,
        wasSubscribed: Bool
    ) -> (Result<Void, Error>) -> Void {
        { [weak self] result in
            DispatchQueue.main.async {
                self?.handleSubscribeResult(
                    result,
                    channelId: channelId,
                    wasSubscribed: wasSubscribed
                )
            }
        }
    }

    /// The channel this video belongs to, from whichever source still knows.
    ///
    /// With no account `channelInfo` is always nil — `fetchChannelInfo` is
    /// token-gated and answers `unauthorized` — and the anonymous watch page
    /// can carry no channel id of its own either. The card the user opened
    /// from is then the only thing left that has it, which is why
    /// `initialVideo` is in this chain: without it the subscribe button was
    /// dead signed out, which is precisely when it matters most.
    var subscribeTargetChannel: SubscribedChannel? {
        let ids = [
            watchPage?.channelInfo?.id,
            watchPage?.video.channelId,
            initialVideo.channelId
        ]
        guard let id = ids.compactMap({ $0 })
            .first(where: { !$0.isEmpty }) else {
            return nil
        }
        let titles = [
            watchPage?.channelInfo?.title,
            watchPage?.video.channelName,
            initialVideo.channelName
        ]
        let avatars = [
            watchPage?.channelInfo?.avatarURL,
            watchPage?.video.channelAvatarURL,
            initialVideo.channelAvatarURL
        ]
        return SubscribedChannel(
            id: id,
            title: titles.compactMap { $0 }
                .first(where: { !$0.isEmpty }) ?? "",
            avatarURL: avatars.compactMap { $0 }
                .first(where: { !$0.isEmpty })
        )
    }

    @objc
    func subscribeButtonTapped() {
        guard let channel = subscribeTargetChannel else {
            // Never silent again: a tap that resolves no channel used to
            // return here without a trace, which reads as a dead button.
            AppLog.subscribe(
                "subscribe tapped but no channel id"
                    + " — page=\(watchPage != nil)"
                    + " info=\(watchPage?.channelInfo?.id != nil)"
                    + " pageVideo=\(watchPage?.video.channelId != nil)"
                    + " initial=\(initialVideo.channelId != nil)"
            )
            return
        }
        let channelId = channel.id
        let wasSubscribed = isSubscribed
        isSubscribed = !wasSubscribed
        if !wasSubscribed {
            Feedback.success()
        }
        subscribeButton.setTitle(
            isSubscribed
                ? "common.subscribed".localized
                : "common.subscribe".localized,
            for: .normal
        )
        subscribeButton.isEnabled = false
        applyTheme()
        let handler = subscribeHandler(channelId: channelId, wasSubscribed: wasSubscribed)
        // Through `SubscribeAction` rather than straight to engagement: with
        // no account the id alone is not enough to store, and this is where
        // the name and avatar are still in hand.
        SubscribeAction.toggle(
            channel: channel,
            wasSubscribed: wasSubscribed,
            engagement: engagementClient,
            completion: handler
        )
    }

    // MARK: - Share & Navigation

    @objc
    func shareTapped() {
        let videoId = watchPage?.video.id ?? initialVideo.id
        guard let url = URL(string: "https://youtu.be/\(videoId)") else {
            return
        }
        let ac = UIActivityViewController(
            activityItems: [url],
            applicationActivities: nil
        )
        if let popover = ac.popoverPresentationController {
            popover.sourceView = shareButton
            popover.sourceRect = shareButton.bounds
        }
        present(ac, animated: true)
    }

    @objc
    func openChannel() {
        let sourceVideo = watchPage?.video ?? initialVideo
        guard let channelId = sourceVideo.channelId else {
            return
        }
        videoRouter.openChannel(id: channelId, name: sourceVideo.channelName)
    }

    @objc
    func closeTapped() {
        exitFullscreenIfNeeded()
        if videoHistory.isEmpty {
            videoRouter.minimize()
        } else {
            goBack()
        }
    }

    func updateLeftBarButton() {
        navigationItem.leftBarButtonItem = videoHistory.isEmpty
            ? makeMinimizeButton()
            : makeBackButton()
    }

    func makeMinimizeButton() -> UIBarButtonItem {
        NavChevron.barButton(
            kind: .minimize,
            target: self,
            action: #selector(closeTapped)
        )
    }

    func makeBackButton() -> UIBarButtonItem {
        NavChevron.barButton(
            kind: .back,
            target: self,
            action: #selector(closeTapped)
        )
    }

    func exitFullscreenIfNeeded() {
        guard let playerView = videoPlayerView,
              playerView.isFullscreen else {
            return
        }
        if UIDevice.current.userInterfaceIdiom == .pad {
            exitFullscreen(playerView: playerView)
        } else {
            // Rotating back to portrait is what leaves fullscreen on iPhone.
            rotateInterface(to: .portrait)
        }
    }
}

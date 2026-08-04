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

    @objc
    func subscribeButtonTapped() {
        guard let channelId = watchPage?.channelInfo?.id
            ?? watchPage?.video.channelId else {
            return
        }
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
        if wasSubscribed {
            engagementClient.unsubscribeFromChannel(channelId: channelId, completion: handler)
        } else {
            engagementClient.subscribeToChannel(channelId: channelId, completion: handler)
        }
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
        navigationController?.pushViewController(
            channelViewControllerFactory(
                channelId,
                sourceVideo.channelName
            ),
            animated: true
        )
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

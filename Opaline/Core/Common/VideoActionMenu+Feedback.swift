import UIKit

// MARK: - Feedback actions

/// "Remove from watch history", "Not interested", "Don't recommend
/// channel", "Hide" — whatever the response this card came from offered.
/// Each arrives worded by YouTube with its own opaque token, so nothing
/// here tells one from another (#105, #106).
extension VideoActionMenu {
    /// What the toast says once the token goes through. The response
    /// carries no wording of its own and the actions are indistinguishable
    /// in it, so the screen that opened the menu names the outcome: a feed
    /// that ranks by taste was retuned, anywhere else the video just went
    /// away. Both strings are YouTube's own, lifted from the official app
    /// in all 13 languages rather than translated here.
    enum FeedbackOutcome {
        case tunedRecommendations, removed

        var message: String {
            switch self {
            case .tunedRecommendations:
                return "video.menu.feedbackTuned".localized
            case .removed:
                return "video.menu.feedbackRemoved".localized
            }
        }
    }

    static func feedbackItems(
        video: Video,
        from presenter: UIViewController,
        outcome: FeedbackOutcome,
        onRemoved: (() -> Void)?,
        engagement: EngagementService = ServiceContainer.engagement
    ) -> [PlayerMenuItem] {
        // The one line that says which actions the response this card came
        // from actually offered, labels and icon types as sent.
        let described = video.feedbackActions
            .map { "\($0.label)[\($0.icon ?? "-")]" }
            .joined(separator: ", ")
        AppLog.innertube("feedback actions for \(video.id): \(described)")
        return video.feedbackActions.map { action in
            PlayerMenuItem(
                title: action.label,
                isDestructive: true,
                iconName: "icon_minus_circle"
            ) {
                engagement.sendFeedback(token: action.token) { result in
                    DispatchQueue.main.async {
                        switch result {
                        case .success:
                            onRemoved?()
                            ToastView.show(outcome.message, in: presenter.view)
                        case .failure:
                            showFailed(in: presenter.view)
                        }
                    }
                }
            }
        }
    }
}

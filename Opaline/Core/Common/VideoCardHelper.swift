import UIKit

/// Shared helpers for video card cells
/// (VideoCell, SubscriptionVideoCell).
enum VideoCardHelper {
    /// Loads channel avatar into the given image view,
    /// using inline URL, ChannelInfoStore, or hiding it.
    /// The `isStillValid` closure is called on main
    /// thread to check cell hasn't been reused.
    static func loadChannelAvatar(
        for video: Video,
        into imageView: ThumbnailImageView,
        isStillValid: @escaping () -> Bool
    ) {
        if let avatarStr = video.channelAvatarURL,
           let url = URL(string: avatarStr) {
            imageView.isHidden = false
            imageView.setImage(url: url)
        } else if let channelId = video.channelId {
            imageView.isHidden = false
            imageView.cancel()
            ChannelInfoStore.shared.fetch(channelId: channelId) { result in
                guard isStillValid(),
                      case .success(let info) = result,
                      let avatarURL = info.avatarURL,
                      let url = URL(string: avatarURL)
                else {
                    return
                }
                imageView.setImage(url: url)
            }
        } else {
            imageView.isHidden = true
            imageView.cancel()
        }
    }

    /// Configures duration label and live badge for a video.
    /// `mixBadge` marks a card that opens a queue rather than a single
    /// video: the server hands a mix playlist to plenty of ordinary music
    /// videos, and the official app labels those the same way.
    static func configureBadges(
        video: Video,
        durationLabel: UILabel,
        liveBadgeView: UILabel?,
        mixBadge: UILabel? = nil
    ) {
        durationLabel.backgroundColor = ThemeManager.shared.durationBackground
        if let mixBadge, video.playlistId != nil {
            // One chip in the corner, not two: the mix label takes the
            // duration's place, the way the official app does it.
            mixBadge.isHidden = false
            durationLabel.isHidden = true
            liveBadgeView?.isHidden = true
            return
        }
        mixBadge?.isHidden = true
        if video.isLive {
            liveBadgeView?.isHidden = false
            // Cells without a badge view of their own reuse the duration slot.
            durationLabel.isHidden = liveBadgeView != nil
            durationLabel.text = " ● LIVE "
            durationLabel.backgroundColor = ThemeManager.shared.liveBadgeBackground
        } else if let duration = video.duration, !duration.isEmpty {
            durationLabel.text = " \(duration) "
            durationLabel.isHidden = false
            liveBadgeView?.isHidden = true
        } else {
            durationLabel.isHidden = true
            liveBadgeView?.isHidden = true
        }
    }

    /// Formats view count + date into a meta string.
    static func metaText(
        viewCount: String?,
        publishedAt: String?,
        separator: String = " • "
    ) -> String {
        let views = viewCount ?? ""
        let date = publishedAt.map(VideoFormatters.formatRelativeDate) ?? ""
        return [views, date].filter { !$0.isEmpty }.joined(separator: separator)
    }
}

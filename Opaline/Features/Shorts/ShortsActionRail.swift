import UIKit

/// The column of actions down the right edge of a short: like, dislike,
/// comments, share. The channel avatar sits next to the channel name at the
/// bottom left instead, as in the official app.
final class ShortsActionRail: UIView {
    enum Action {
        /// Not a rail button — the overlay's channel row reports through the
        /// same vocabulary so the controller has one action handler.
        case channel
        case like
        case dislike
        case comments
        case share
    }

    var onAction: ((Action) -> Void)?

    private let like = ShortsActionButton(icon: "icon_thumb_up")
    private let dislike = ShortsActionButton(icon: "icon_thumb_down")
    private let comments = ShortsActionButton(icon: "icon_comment")
    private let share = ShortsActionButton(icon: "icon_share")

    override init(frame: CGRect) {
        super.init(frame: frame)
        setupStack()
        wireActions()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    /// Counts are shown only where the official app shows them — dislikes
    /// have no public count and share never has one. An unknown count keeps
    /// its space rather than collapsing: the values arrive with the watch
    /// page, a moment after the short starts, and a collapsing label makes
    /// the whole rail jump.
    func configure(
        likeCount: String?,
        commentCount: String?,
        likeStatus: LikeStatus?
    ) {
        like.count = likeCount
        comments.count = commentCount
        like.isHighlighted = likeStatus == .like
        dislike.isHighlighted = likeStatus == .dislike
    }

    private func setupStack() {
        let stack = UIStackView(arrangedSubviews: [
            like, dislike, comments, share
        ])
        stack.axis = .vertical
        stack.spacing = 20
        stack.alignment = .center
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor)
        ])
    }

    private func wireActions() {
        let pairs: [(ShortsActionButton, Action)] = [
            (like, .like), (dislike, .dislike),
            (comments, .comments), (share, .share)
        ]
        for (button, action) in pairs {
            button.onTap = { [weak self] in self?.onAction?(action) }
        }
    }
}

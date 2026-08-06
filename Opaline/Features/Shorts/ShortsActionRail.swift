import UIKit

/// The column of actions down the right edge of a short: channel avatar,
/// like, dislike, comments, share — the official app's arrangement.
final class ShortsActionRail: UIView {
    enum Action {
        case channel
        case like
        case dislike
        case comments
        case share
    }

    var onAction: ((Action) -> Void)?

    let avatar = ThumbnailImageView(frame: .zero)
    private let like = ShortsActionButton(icon: "icon_thumb_up")
    private let dislike = ShortsActionButton(icon: "icon_thumb_down")
    private let comments = ShortsActionButton(icon: "icon_comment")
    private let share = ShortsActionButton(icon: "icon_share")

    override init(frame: CGRect) {
        super.init(frame: frame)
        setupAvatar()
        setupStack()
        wireActions()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    /// Counts are shown only where the official app shows them — dislikes
    /// have no public count and share never has one.
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

    func setAvatar(url: String?) {
        avatar.isHidden = url == nil
        guard let url, let parsed = URL(string: url) else {
            return
        }
        avatar.setImage(url: parsed)
    }

    private func setupAvatar() {
        avatar.translatesAutoresizingMaskIntoConstraints = false
        avatar.maxPixelSize = 96
        avatar.layer.cornerRadius = 20
        avatar.layer.borderWidth = 1
        avatar.layer.borderColor = UIColor.white.cgColor
        avatar.clipsToBounds = true
        avatar.isUserInteractionEnabled = true
        avatar.addGestureRecognizer(
            UITapGestureRecognizer(
                target: self, action: #selector(avatarTapped)
            )
        )
        NSLayoutConstraint.activate([
            avatar.widthAnchor.constraint(equalToConstant: 40),
            avatar.heightAnchor.constraint(equalToConstant: 40)
        ])
    }

    private func setupStack() {
        let stack = UIStackView(arrangedSubviews: [
            avatar, like, dislike, comments, share
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

    @objc
    private func avatarTapped() {
        onAction?(.channel)
    }
}

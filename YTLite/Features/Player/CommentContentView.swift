import UIKit

/// Renders one comment's avatar, author, meta and (linkified) body.
///
/// Built once and reconfigured, never rebuilt per comment — used both as
/// `CommentCell`'s content (inside the reusable expanded table) and as the
/// single collapsed-preview row, so at most a handful of instances ever
/// exist regardless of how many comments the page returned.
final class CommentContentView: UIView {
    private let avatarView = ThumbnailImageView(frame: .zero)
    private let authorLabel = UILabel()
    private let metaLabel = UILabel()
    private let contentTextView = UITextView()
    /// Kept so a theme switch can re-render: the body's colours are baked
    /// into its attributed string, so they cannot be restyled in place.
    private var comment: Comment?
    private weak var linkDelegate: UITextViewDelegate?

    override init(frame: CGRect) {
        super.init(frame: frame)
        setup()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("Not implemented")
    }

    func configure(_ comment: Comment, linkDelegate: UITextViewDelegate) {
        self.comment = comment
        self.linkDelegate = linkDelegate
        let url = comment.authorAvatarURL.flatMap { URL(string: $0) }
        avatarView.setAvatar(url: url, name: comment.authorName)
        authorLabel.text = comment.isPinned
            ? "player.comments.pinned".localized(with: comment.authorName)
            : comment.authorName
        metaLabel.text = [
            comment.publishedTime,
            comment.likeCount.map { "player.comments.likes".localized(with: $0) },
            comment.replyCount.map { "player.comments.replies".localized(with: $0) }
        ]
        .compactMap { $0 }
        .filter { !$0.isEmpty }
        .joined(separator: " • ")
        let theme = ThemeManager.shared
        contentTextView.attributedText = LinkifiedText.attributedString(
            from: comment.content,
            font: UIFont.systemFont(ofSize: 13),
            color: theme.primaryText,
            includeTimestamps: true
        )
        contentTextView.linkTextAttributes = [.foregroundColor: theme.accent]
        contentTextView.delegate = linkDelegate
        authorLabel.textColor = theme.primaryText
        metaLabel.textColor = theme.secondaryText
    }

    /// Re-renders with the current theme. Cheap enough to call on every
    /// theme switch: it re-runs one linkify pass for one comment.
    func applyTheme() {
        guard let comment, let linkDelegate else {
            return
        }
        configure(comment, linkDelegate: linkDelegate)
    }

    private func setup() {
        translatesAutoresizingMaskIntoConstraints = false
        avatarView.layer.cornerRadius = 16
        avatarView.layer.masksToBounds = true
        authorLabel.font = UIFont.systemFont(ofSize: 13, weight: .semibold)
        authorLabel.numberOfLines = 1
        metaLabel.font = UIFont.systemFont(ofSize: 11)
        metaLabel.numberOfLines = 0
        LinkifiedText.configure(contentTextView)
        for item in [avatarView, authorLabel, metaLabel, contentTextView] {
            item.translatesAutoresizingMaskIntoConstraints = false
            addSubview(item)
        }
        activateConstraints()
    }

    private func activateConstraints() {
        NSLayoutConstraint.activate([
            avatarView.topAnchor.constraint(equalTo: topAnchor),
            avatarView.leadingAnchor.constraint(equalTo: leadingAnchor),
            avatarView.widthAnchor.constraint(equalToConstant: 32),
            avatarView.heightAnchor.constraint(equalToConstant: 32),

            authorLabel.topAnchor.constraint(equalTo: topAnchor),
            authorLabel.leadingAnchor.constraint(equalTo: avatarView.trailingAnchor, constant: 12),
            authorLabel.trailingAnchor.constraint(equalTo: trailingAnchor),

            metaLabel.topAnchor.constraint(equalTo: authorLabel.bottomAnchor, constant: 2),
            metaLabel.leadingAnchor.constraint(equalTo: authorLabel.leadingAnchor),
            metaLabel.trailingAnchor.constraint(equalTo: authorLabel.trailingAnchor),

            contentTextView.topAnchor.constraint(equalTo: metaLabel.bottomAnchor, constant: 6),
            contentTextView.leadingAnchor.constraint(equalTo: authorLabel.leadingAnchor),
            contentTextView.trailingAnchor.constraint(equalTo: authorLabel.trailingAnchor),
            contentTextView.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
    }
}

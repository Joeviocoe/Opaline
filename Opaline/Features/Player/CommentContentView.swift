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
    private let contentTextView = UITextView()
    /// Read-only like counter under the body — the API only offers the
    /// action to a cookie-authenticated session, so there is nothing to tap.
    private let likeStack = UIStackView()
    private let likeIcon = UIImageView()
    private let likeLabel = UILabel()
    /// Kept so a theme switch can re-render: the body's colours are baked
    /// into its attributed string, so they cannot be restyled in place.
    private var comment: Comment?
    private var isReply = false
    private weak var linkDelegate: UITextViewDelegate?
    private var avatarSize: NSLayoutConstraint?
    private var likeBottom: NSLayoutConstraint?
    private var bodyBottom: NSLayoutConstraint?

    override init(frame: CGRect) {
        super.init(frame: frame)
        setup()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("Not implemented")
    }

    func configure(
        _ comment: Comment,
        linkDelegate: UITextViewDelegate,
        isReply: Bool = false
    ) {
        self.comment = comment
        self.isReply = isReply
        self.linkDelegate = linkDelegate
        let url = comment.authorAvatarURL.flatMap { URL(string: $0) }
        avatarView.setAvatar(url: url, name: comment.authorName)
        avatarSize?.constant = isReply ? 24 : 32
        avatarView.layer.cornerRadius = isReply ? 12 : 16
        // One grey line above the body, as in the official app: who and
        // when. Likes moved to the action row, replies to their own row.
        let name = comment.isPinned
            ? "player.comments.pinned".localized(with: comment.authorName)
            : comment.authorName
        authorLabel.text = [name, comment.publishedTime]
            .compactMap { $0 }
            .filter { !$0.isEmpty }
            .joined(separator: " • ")
        // A comment with no likes shows no counter at all rather than "0".
        let hasLikes = !(comment.likeCount ?? "").isEmpty
        likeLabel.text = comment.likeCount
        likeStack.isHidden = !hasLikes
        bodyBottom?.isActive = false
        likeBottom?.isActive = hasLikes
        bodyBottom?.isActive = !hasLikes
        let theme = ThemeManager.shared
        likeIcon.tintColor = theme.secondaryText
        likeLabel.textColor = theme.secondaryText
        contentTextView.attributedText = CommentBodyCache.body(for: comment)
        contentTextView.linkTextAttributes = [.foregroundColor: theme.accent]
        contentTextView.delegate = linkDelegate
        authorLabel.textColor = theme.secondaryText
    }

    /// Re-renders with the current theme. Cheap enough to call on every
    /// theme switch: it re-runs one linkify pass for one comment.
    func applyTheme() {
        guard let comment = comment, let linkDelegate = linkDelegate else {
            return
        }
        configure(comment, linkDelegate: linkDelegate, isReply: isReply)
    }

    private func setup() {
        translatesAutoresizingMaskIntoConstraints = false
        avatarView.layer.cornerRadius = 16
        avatarView.layer.masksToBounds = true
        authorLabel.font = UIFont.systemFont(ofSize: 12)
        authorLabel.numberOfLines = 1
        LinkifiedText.configure(contentTextView)
        likeIcon.image = LegacyAssets.image("icon_thumb_up")?
            .withRenderingMode(.alwaysTemplate)
        likeIcon.contentMode = .scaleAspectFit
        likeLabel.font = UIFont.systemFont(ofSize: 12)
        likeStack.axis = .horizontal
        likeStack.alignment = .center
        likeStack.spacing = 6
        likeStack.addArrangedSubview(likeIcon)
        likeStack.addArrangedSubview(likeLabel)
        for item in [avatarView, authorLabel, contentTextView, likeStack] {
            item.translatesAutoresizingMaskIntoConstraints = false
            addSubview(item)
        }
        activateConstraints()
    }

    private func activateConstraints() {
        let size = avatarView.widthAnchor.constraint(equalToConstant: 32)
        avatarSize = size
        NSLayoutConstraint.activate([
            avatarView.topAnchor.constraint(equalTo: topAnchor),
            avatarView.leadingAnchor.constraint(equalTo: leadingAnchor),
            size,
            avatarView.heightAnchor.constraint(equalTo: avatarView.widthAnchor),

            authorLabel.topAnchor.constraint(equalTo: topAnchor),
            authorLabel.leadingAnchor.constraint(equalTo: avatarView.trailingAnchor, constant: 12),
            authorLabel.trailingAnchor.constraint(equalTo: trailingAnchor),

            contentTextView.topAnchor.constraint(equalTo: authorLabel.bottomAnchor, constant: 4),
            contentTextView.leadingAnchor.constraint(equalTo: authorLabel.leadingAnchor),
            contentTextView.trailingAnchor.constraint(equalTo: authorLabel.trailingAnchor),

            likeIcon.widthAnchor.constraint(equalToConstant: 14),
            likeIcon.heightAnchor.constraint(equalToConstant: 14),
            likeStack.topAnchor.constraint(equalTo: contentTextView.bottomAnchor, constant: 6),
            likeStack.leadingAnchor.constraint(equalTo: authorLabel.leadingAnchor)
        ])
        // A hidden stack view still claims its height, so which view reaches
        // the bottom edge is swapped instead of hidden.
        likeBottom = likeStack.bottomAnchor.constraint(equalTo: bottomAnchor)
        bodyBottom = contentTextView.bottomAnchor.constraint(equalTo: bottomAnchor)
        likeBottom?.isActive = true
    }
}

/// Linkifying a comment runs an `NSDataDetector` and a regex over its body —
/// far too much to redo on every cell reuse while scrolling a long list. The
/// result depends only on the text and the theme's colours, so it is kept
/// until the theme flips.
private enum CommentBodyCache {
    /// ponytail: dropped wholesale when full; comments are short-lived
    /// per-video state, so an LRU would buy nothing here.
    private static let limit = 500

    private static var entries: [String: NSAttributedString] = [:]
    private static var isDark = ThemeManager.shared.isDark

    static func body(for comment: Comment) -> NSAttributedString {
        let theme = ThemeManager.shared
        if isDark != theme.isDark {
            isDark = theme.isDark
            entries.removeAll()
        }
        if let cached = entries[comment.id] {
            return cached
        }
        let built = LinkifiedText.attributedString(
            from: comment.content,
            font: UIFont.systemFont(ofSize: 13),
            color: theme.primaryText,
            includeTimestamps: true
        )
        if entries.count >= limit {
            entries.removeAll()
        }
        entries[comment.id] = built
        return built
    }
}

import UIKit

/// One reusable row in the expanded comments table — the crux of the
/// section's cell reuse: only as many `CommentCell`s exist as fit on
/// screen, however many comments the page returned.
final class CommentCell: UITableViewCell {
    static let reuseId = "CommentCell"

    /// Indent of a reply row relative to a top-level comment.
    static let replyIndent: CGFloat = 44

    private let content = CommentContentView()
    private var leading: NSLayoutConstraint?

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        selectionStyle = .none
        // A table view cell is opaque white by default. Left alone it hides
        // the themed table underneath and, in the dark theme, renders white
        // text on white.
        backgroundColor = .clear
        contentView.backgroundColor = .clear
        contentView.addSubview(content)
        let leading = content.leadingAnchor.constraint(
            equalTo: contentView.leadingAnchor, constant: 16
        )
        self.leading = leading
        NSLayoutConstraint.activate([
            content.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 12),
            leading,
            content.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
            content.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -6)
        ])
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
        leading?.constant = isReply ? 16 + Self.replyIndent : 16
        content.configure(comment, linkDelegate: linkDelegate, isReply: isReply)
    }
}

/// The "961 replies" / "Hide replies" row: a rounded grey pill with a
/// chevron, matching the official app rather than the bare blue text the
/// status cell would give it.
final class CommentReplyCell: UITableViewCell {
    static let reuseId = "CommentReplyCell"

    private let pill = UIView()
    private let chevron = UIImageView()
    private let label = UILabel()

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        selectionStyle = .none
        backgroundColor = .clear
        contentView.backgroundColor = .clear
        setup()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("Not implemented")
    }

    /// A symbol image is boxed with the font's own vertical padding, so
    /// aspect-fitting one into a 10pt-tall slot shrank the visible stroke to
    /// a hairline. The glyph is sized by its point size and drawn 1:1
    /// instead. `NavChevron` still covers iOS 12 (no SF Symbols); its
    /// 22×13 bar-button drawing is redrawn down to pill scale.
    private static func chevronImage() -> UIImage? {
        guard #available(iOS 13.0, *) else {
            let size = CGSize(width: 15, height: 9)
            return UIGraphicsImageRenderer(size: size).image { _ in
                NavChevron.image(kind: .minimize)?
                    .draw(in: CGRect(origin: .zero, size: size))
            }
        }
        let cfg = UIImage.SymbolConfiguration(pointSize: 15, weight: .bold)
        return UIImage(systemName: "chevron.down", withConfiguration: cfg)
    }

    func configure(text: String, isExpanded: Bool) {
        label.text = text
        let theme = ThemeManager.shared
        label.textColor = theme.primaryText
        chevron.tintColor = theme.primaryText
        chevron.transform = isExpanded
            ? CGAffineTransform(rotationAngle: .pi)
            : .identity
        pill.backgroundColor = theme.primaryText.withAlphaComponent(0.12)
    }

    private func setup() {
        pill.layer.cornerRadius = 16
        pill.layer.masksToBounds = true
        label.font = UIFont.systemFont(ofSize: 13, weight: .semibold)
        chevron.image = Self.chevronImage()?.withRenderingMode(.alwaysTemplate)
        chevron.contentMode = .center
        for item in [pill, chevron, label] {
            item.translatesAutoresizingMaskIntoConstraints = false
        }
        contentView.addSubview(pill)
        pill.addSubview(chevron)
        pill.addSubview(label)
        let cv = contentView
        NSLayoutConstraint.activate([
            pill.topAnchor.constraint(equalTo: cv.topAnchor, constant: 2),
            pill.bottomAnchor.constraint(equalTo: cv.bottomAnchor, constant: -6),
            pill.leadingAnchor.constraint(
                equalTo: cv.leadingAnchor, constant: 16 + CommentCell.replyIndent
            ),
            pill.trailingAnchor.constraint(lessThanOrEqualTo: cv.trailingAnchor, constant: -16),
            pill.heightAnchor.constraint(equalToConstant: 32),

            chevron.leadingAnchor.constraint(equalTo: pill.leadingAnchor, constant: 12),
            chevron.centerYAnchor.constraint(equalTo: pill.centerYAnchor),

            label.leadingAnchor.constraint(equalTo: chevron.trailingAnchor, constant: 8),
            label.trailingAnchor.constraint(equalTo: pill.trailingAnchor, constant: -14),
            label.centerYAnchor.constraint(equalTo: pill.centerYAnchor)
        ])
    }
}

/// Renders the table's non-comment rows: the loading skeleton, the empty
/// message and the trailing "load more" row — everything that isn't an
/// actual comment, sharing one cell class since none of them need more
/// than a label (and, for the skeleton, the shared shimmer overlay).
final class CommentStatusCell: UITableViewCell {
    static let reuseId = "CommentStatusCell"

    private let messageLabel = UILabel()
    private let skeletonBox = UIView()

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        selectionStyle = .none
        backgroundColor = .clear
        contentView.backgroundColor = .clear
        setup()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("Not implemented")
    }

    func configure(text: String?, isSkeleton: Bool) {
        skeletonBox.isHidden = !isSkeleton
        messageLabel.isHidden = isSkeleton
        // `.default` paints the row nearly white on tap, which reads as a
        // material-style ripple and looks nothing like the rest of the app.
        // The row is a text button; its own colour is the affordance.
        selectionStyle = .none
        if isSkeleton {
            skeletonBox.showSkeleton()
            return
        }
        skeletonBox.hideSkeleton()
        messageLabel.text = text
        messageLabel.textColor = ThemeManager.shared.secondaryText
    }

    private func setup() {
        messageLabel.numberOfLines = 0
        messageLabel.font = UIFont.systemFont(ofSize: 13)
        skeletonBox.layer.cornerRadius = 8
        skeletonBox.layer.masksToBounds = true
        skeletonBox.isHidden = true
        for item in [messageLabel, skeletonBox] {
            item.translatesAutoresizingMaskIntoConstraints = false
            contentView.addSubview(item)
        }
        let cv = contentView
        let height = skeletonBox.heightAnchor.constraint(equalToConstant: 56)
        NSLayoutConstraint.activate([
            messageLabel.topAnchor.constraint(equalTo: cv.topAnchor, constant: 12),
            messageLabel.leadingAnchor.constraint(equalTo: cv.leadingAnchor, constant: 16),
            messageLabel.trailingAnchor.constraint(equalTo: cv.trailingAnchor, constant: -16),
            messageLabel.bottomAnchor.constraint(equalTo: cv.bottomAnchor, constant: -12),
            skeletonBox.topAnchor.constraint(equalTo: cv.topAnchor, constant: 8),
            skeletonBox.leadingAnchor.constraint(equalTo: cv.leadingAnchor, constant: 16),
            skeletonBox.trailingAnchor.constraint(equalTo: cv.trailingAnchor, constant: -16),
            skeletonBox.bottomAnchor.constraint(equalTo: cv.bottomAnchor, constant: -8),
            height
        ])
    }
}

import UIKit

/// One reusable row in the expanded comments table — the crux of the
/// section's cell reuse: only as many `CommentCell`s exist as fit on
/// screen, however many comments the page returned.
final class CommentCell: UITableViewCell {
    static let reuseId = "CommentCell"

    private let content = CommentContentView()

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        selectionStyle = .none
        // A table view cell is opaque white by default. Left alone it hides
        // the themed table underneath and, in the dark theme, renders white
        // text on white.
        backgroundColor = .clear
        contentView.backgroundColor = .clear
        contentView.addSubview(content)
        NSLayoutConstraint.activate([
            content.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 10),
            content.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            content.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
            content.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -10)
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("Not implemented")
    }

    func configure(_ comment: Comment, linkDelegate: UITextViewDelegate) {
        content.configure(comment, linkDelegate: linkDelegate)
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

    func configure(text: String?, isSkeleton: Bool, isAction: Bool) {
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
        let theme = ThemeManager.shared
        messageLabel.textColor = isAction ? theme.accent : theme.secondaryText
        messageLabel.font = isAction
            ? UIFont.systemFont(ofSize: 13, weight: .semibold)
            : UIFont.systemFont(ofSize: 13)
    }

    private func setup() {
        messageLabel.numberOfLines = 0
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

import UIKit

/// The strip along the bottom of the watch screen while a mix or playlist is
/// playing: what comes next, what the queue is, and a tap to open the panel
/// that lists it. It belongs to the watch screen and stays there — the mini
/// player is a separate thing and is untouched by it.
final class QueueBarView: UIView {
    static let height: CGFloat = 56

    var onTap: (() -> Void)?

    private let nextLabel = UILabel()
    private let queueLabel = UILabel()
    private let chevron = UIImageView()

    override init(frame: CGRect) {
        super.init(frame: frame)
        setup()
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(applyTheme),
            name: ThemeManager.didChangeNotification,
            object: nil
        )
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("Not implemented")
    }

    /// `next` is nil at the end of the queue — the strip then only names
    /// what is playing, rather than promising a video that isn't coming.
    func configure(queueTitle: String, current: String, next: String?) {
        nextLabel.text = next.map {
            String(
                format: "player.queue.upNext".localized,
                $0
            )
        } ?? current
        queueLabel.text = next == nil
            ? queueTitle
            : "\(queueTitle) – \(current)"
    }

    @objc
    func applyTheme() {
        let theme = ThemeManager.shared
        backgroundColor = theme.surface
        nextLabel.textColor = theme.primaryText
        queueLabel.textColor = theme.secondaryText
        chevron.tintColor = theme.primaryText
    }

    private func setup() {
        translatesAutoresizingMaskIntoConstraints = false
        layer.cornerRadius = 12
        layer.masksToBounds = true
        nextLabel.font = UIFont.systemFont(ofSize: 14, weight: .medium)
        queueLabel.font = UIFont.systemFont(ofSize: 13)
        for label in [nextLabel, queueLabel] {
            label.lineBreakMode = .byTruncatingTail
        }
        chevron.image = PlayerIcons.playerIcon(
            "icon_chevron_up",
            size: 18
        )
        chevron.contentMode = .scaleAspectFit
        chevron.setContentHuggingPriority(.required, for: .horizontal)
        layoutRow()
        addGestureRecognizer(
            UITapGestureRecognizer(
                target: self,
                action: #selector(tapped)
            )
        )
        applyTheme()
    }

    private func layoutRow() {
        let text = UIStackView(
            arrangedSubviews: [nextLabel, queueLabel]
        )
        text.axis = .vertical
        text.spacing = 2
        let row = UIStackView(arrangedSubviews: [text, chevron])
        row.axis = .horizontal
        row.alignment = .center
        row.spacing = 12
        row.translatesAutoresizingMaskIntoConstraints = false
        addSubview(row)
        NSLayoutConstraint.activate([
            row.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
            row.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16),
            row.centerYAnchor.constraint(equalTo: centerYAnchor),
            chevron.widthAnchor.constraint(equalToConstant: 18)
        ])
    }

    @objc
    private func tapped() {
        onTap?()
    }
}

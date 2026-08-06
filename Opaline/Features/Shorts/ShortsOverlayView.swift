import UIKit

/// The chrome over the playing short: the scrim, the channel row, the title
/// and the action rail. It lives in the view controller rather than in the
/// cell so it can sit inside the screen's safe area — the cells run edge to
/// edge under the transparent tab bar, and anything pinned to a cell ends up
/// clipped by the tab bar or the display's rounded corners.
final class ShortsOverlayView: UIView {
    let rail = ShortsActionRail()

    private let scrim = GradientView()
    private let titleLabel = UILabel()
    private let channelButton = UIButton(type: .system)
    private let viewsLabel = UILabel()
    private var video: Video?

    var onAction: ((ShortsActionRail.Action, Video) -> Void)?

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = true
        setupScrim()
        setupRail()
        setupText()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    /// Taps pass through to the player everywhere except on the controls,
    /// so tapping the video still pauses it.
    override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
        subviews.contains {
            !$0.isHidden && $0.isUserInteractionEnabled
                && $0.frame.contains(point)
        }
    }

    func configure(with video: Video) {
        self.video = video
        titleLabel.text = video.title
        channelButton.setTitle(video.channelName, for: .normal)
        channelButton.isHidden = video.channelName.isEmpty
        viewsLabel.text = video.viewCount
    }

    func configure(
        likeCount: String?,
        commentCount: String?,
        likeStatus: LikeStatus?,
        avatarURL: String?
    ) {
        rail.configure(
            likeCount: likeCount,
            commentCount: commentCount,
            likeStatus: likeStatus
        )
        rail.setAvatar(url: avatarURL)
    }

    @objc
    private func channelTapped() {
        emit(.channel)
    }

    private func emit(_ action: ShortsActionRail.Action) {
        guard let video else {
            return
        }
        onAction?(action, video)
    }

    private func setupScrim() {
        scrim.translatesAutoresizingMaskIntoConstraints = false
        scrim.isUserInteractionEnabled = false
        addSubview(scrim)
        NSLayoutConstraint.activate([
            scrim.leadingAnchor.constraint(equalTo: leadingAnchor),
            scrim.trailingAnchor.constraint(equalTo: trailingAnchor),
            scrim.bottomAnchor.constraint(equalTo: bottomAnchor),
            scrim.heightAnchor.constraint(
                equalTo: heightAnchor, multiplier: 0.45
            )
        ])
    }

    private func setupRail() {
        rail.translatesAutoresizingMaskIntoConstraints = false
        rail.onAction = { [weak self] action in
            self?.emit(action)
        }
        addSubview(rail)
        NSLayoutConstraint.activate([
            rail.trailingAnchor.constraint(
                equalTo: trailingAnchor, constant: -12
            ),
            rail.bottomAnchor.constraint(
                equalTo: bottomAnchor, constant: -12
            )
        ])
    }

    private func setupText() {
        titleLabel.textColor = .white
        titleLabel.font = .systemFont(ofSize: 15, weight: .medium)
        titleLabel.numberOfLines = 2
        channelButton.setTitleColor(.white, for: .normal)
        channelButton.titleLabel?.font = .systemFont(ofSize: 14, weight: .semibold)
        channelButton.contentHorizontalAlignment = .leading
        channelButton.addTarget(
            self, action: #selector(channelTapped), for: .touchUpInside
        )
        viewsLabel.textColor = UIColor.white.withAlphaComponent(0.8)
        viewsLabel.font = .systemFont(ofSize: 13)

        let stack = UIStackView(arrangedSubviews: [
            channelButton, titleLabel, viewsLabel
        ])
        stack.axis = .vertical
        stack.spacing = 4
        stack.alignment = .leading
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(
                equalTo: leadingAnchor, constant: 16
            ),
            stack.trailingAnchor.constraint(
                lessThanOrEqualTo: rail.leadingAnchor, constant: -12
            ),
            stack.bottomAnchor.constraint(
                equalTo: bottomAnchor, constant: -12
            )
        ])
    }
}

/// Bottom-up black fade. Without it white overlay text is unreadable over a
/// bright short — the official app draws the same scrim.
final class GradientView: UIView {
    override static var layerClass: AnyClass { CAGradientLayer.self }

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        let gradient = layer as? CAGradientLayer
        gradient?.colors = [
            UIColor.clear.cgColor,
            UIColor.black.withAlphaComponent(0.7).cgColor
        ]
        gradient?.locations = [0, 1]
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

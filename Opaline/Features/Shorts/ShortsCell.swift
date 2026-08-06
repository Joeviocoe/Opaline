import UIKit

/// One full-screen page of the Shorts feed: the poster frame, the overlay,
/// and a slot the shared player view is moved into while this page is current.
final class ShortsCell: UICollectionViewCell {
    static let reuseIdentifier = "ShortsCell"

    /// The shared `ShortsPlayerView` is added here when this page is current.
    let playerContainer = UIView()
    private let poster = ThumbnailImageView(frame: .zero)
    private let titleLabel = UILabel()
    private let channelButton = UIButton(type: .system)
    private let viewsLabel = UILabel()
    private var video: Video?

    var onChannelTap: ((Video) -> Void)?

    override init(frame: CGRect) {
        super.init(frame: frame)
        contentView.backgroundColor = .black
        setupPoster()
        setupPlayerContainer()
        setupOverlay()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        poster.cancel()
        poster.image = nil
        poster.isHidden = false
    }

    func configure(with video: Video) {
        self.video = video
        titleLabel.text = video.title
        channelButton.setTitle(video.channelName, for: .normal)
        channelButton.isHidden = video.channelName.isEmpty
        viewsLabel.text = video.viewCount
        if let url = URL(string: video.thumbnailURL) {
            poster.setImage(url: url)
        }
    }

    @objc
    private func channelTapped() {
        guard let video else {
            return
        }
        onChannelTap?(video)
    }

    // MARK: - Layout

    private func setupPoster() {
        poster.translatesAutoresizingMaskIntoConstraints = false
        poster.contentMode = .scaleAspectFit
        poster.backgroundColor = .black
        contentView.addSubview(poster)
        pin(poster)
    }

    private func setupPlayerContainer() {
        playerContainer.translatesAutoresizingMaskIntoConstraints = false
        playerContainer.backgroundColor = .clear
        contentView.addSubview(playerContainer)
        pin(playerContainer)
    }

    private func pin(_ subview: UIView) {
        NSLayoutConstraint.activate([
            subview.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            subview.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            subview.topAnchor.constraint(equalTo: contentView.topAnchor),
            subview.bottomAnchor.constraint(equalTo: contentView.bottomAnchor)
        ])
    }

    private func styleOverlayLabels() {
        titleLabel.textColor = .white
        titleLabel.font = .systemFont(ofSize: 15, weight: .medium)
        titleLabel.numberOfLines = 2
        channelButton.setTitleColor(.white, for: .normal)
        channelButton.titleLabel?.font = .systemFont(ofSize: 14, weight: .semibold)
        channelButton.addTarget(
            self, action: #selector(channelTapped), for: .touchUpInside
        )
        channelButton.contentHorizontalAlignment = .leading
        viewsLabel.textColor = UIColor.white.withAlphaComponent(0.8)
        viewsLabel.font = .systemFont(ofSize: 13)
    }

    private func setupOverlay() {
        styleOverlayLabels()
        let stack = UIStackView(arrangedSubviews: [
            channelButton, titleLabel, viewsLabel
        ])
        stack.axis = .vertical
        stack.spacing = 4
        stack.alignment = .leading
        stack.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(
                equalTo: contentView.leadingAnchor, constant: 16
            ),
            stack.trailingAnchor.constraint(
                lessThanOrEqualTo: contentView.trailingAnchor, constant: -16
            ),
            stack.bottomAnchor.constraint(
                equalTo: contentView.safeAreaLayoutGuide.bottomAnchor,
                constant: -24
            )
        ])
    }
}

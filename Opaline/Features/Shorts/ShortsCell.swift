import UIKit

/// One full-screen page of the Shorts feed: the poster frame and the slot the
/// shared player view is moved into while this page is current. The overlay
/// belongs to the view controller — only one is ever visible, and it has to
/// sit in the screen's safe area rather than the cell's.
final class ShortsCell: UICollectionViewCell {
    static let reuseIdentifier = "ShortsCell"

    /// The shared `ShortsPlayerView` is added here when this page is current.
    let playerContainer = UIView()
    private let poster = ThumbnailImageView(frame: .zero)

    override init(frame: CGRect) {
        super.init(frame: frame)
        contentView.backgroundColor = .black
        setupPoster()
        setupPlayerContainer()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    /// Matches the player's gravity, which fits rather than fills once the
    /// screen is on its side.
    override func layoutSubviews() {
        super.layoutSubviews()
        poster.contentMode = bounds.height > bounds.width
            ? .scaleAspectFill : .scaleAspectFit
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        poster.cancel()
        poster.image = nil
    }

    func configure(with video: Video) {
        // The short's own first frame, not the feed's thumbnail: a channel
        // or subscriptions item carries a landscape cover, whose centre crop
        // does not line up with the video and so visibly jumps the moment
        // playback starts. frame0 is exactly what the player draws first.
        if let url = URL(
            string: "https://i.ytimg.com/vi/\(video.id)/frame0.jpg"
        ) {
            poster.setImage(url: url)
        }
    }

    private func setupPoster() {
        poster.translatesAutoresizingMaskIntoConstraints = false
        // Fill, matching the gravity nearly every short ends up with, so the
        // poster and the first frame line up. A square short is the exception
        // and still steps out of the crop when it starts.
        poster.contentMode = .scaleAspectFill
        poster.clipsToBounds = true
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

    /// Full width, from the top of the screen down to the tab bar — not the
    /// whole cell. The official app fills that region, which is why a 9:16
    /// short loses about a tenth of its width there instead of a fifth, and
    /// why a short as tall as the region shows no bands at all.
    private func pin(_ subview: UIView) {
        NSLayoutConstraint.activate([
            subview.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            subview.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            subview.topAnchor.constraint(equalTo: contentView.topAnchor),
            subview.bottomAnchor.constraint(
                equalTo: contentView.safeAreaLayoutGuide.bottomAnchor
            )
        ])
    }
}

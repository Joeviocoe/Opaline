import UIKit

/// The sliding panel used by both orientations and by both of the things
/// that fill it — comments and the playing queue. A grab handle, a header
/// (a title and optional buttons) and whatever list view it was handed,
/// already configured. Portrait pins this behind a draggable top
/// constraint owned by `WatchViewController+Sheet`; landscape drops it into
/// the sidebar slot with no drag. The table view itself is untouched — this
/// type only owns the chrome around it.
final class PlayerSheetView: UIView {
    let titleLabel = UILabel()
    /// Handle + header together — the pan gesture in
    /// `WatchViewController+Sheet` is installed on this region so
    /// the table view keeps its own scroll gesture untouched.
    let dragRegion = UIView()
    /// Tapped sort option, by index into whatever `setSortOptions` was last
    /// given.
    var onSelectSort: ((Int) -> Void)?

    private let handle = UIView()
    private let headerStack = UIStackView()
    /// A row of its own under the title, not beside it — a long queue name
    /// squeezed the buttons off the edge.
    private let buttonRow = UIView()
    private let buttonStack = UIStackView()
    private let sortBar = ChipBarView()
    /// Grab handle, title and sort bar stacked together — a stack view so
    /// hiding the sort bar collapses the space it took with it.
    private let chrome = UIStackView()
    /// The list itself: a table view for comments, a collection view for the
    /// queue. Both are scroll views and the chrome treats them the same.
    private let list: UIScrollView

    init(list: UIScrollView) {
        self.list = list
        super.init(frame: .zero)
        setup()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("Not implemented")
    }

    func applyTheme(_ theme: ThemeManager) {
        backgroundColor = theme.surface
        handle.backgroundColor = theme.secondaryText
        titleLabel.textColor = theme.primaryText
        list.backgroundColor = theme.surface
        for button in buttonStack.arrangedSubviews {
            button.tintColor = theme.primaryText
        }
    }

    /// Buttons on the trailing edge of the header, in the order given.
    func setHeaderButtons(_ buttons: [UIButton]) {
        for existing in buttonStack.arrangedSubviews {
            existing.removeFromSuperview()
        }
        for button in buttons {
            buttonStack.addArrangedSubview(button)
        }
        buttonRow.isHidden = buttons.isEmpty
    }

    /// Shows the server's sort choices; an empty list hides the bar (replies
    /// pages and videos with a single order don't send one).
    func setSortOptions(_ options: [CommentSortOption]) {
        sortBar.isHidden = options.count < 2
        guard options.count > 1 else {
            return
        }
        sortBar.setLabels(
            options.map(\.title),
            selected: options.firstIndex(where: \.isSelected) ?? 0
        )
    }

    private func setup() {
        translatesAutoresizingMaskIntoConstraints = false
        layer.cornerRadius = 16
        layer.maskedCorners = [.layerMinXMinYCorner, .layerMaxXMinYCorner]
        layer.masksToBounds = true
        handle.layer.cornerRadius = 2.5
        handle.layer.masksToBounds = true
        titleLabel.font = UIFont.systemFont(ofSize: 16, weight: .semibold)
        titleLabel.setContentHuggingPriority(.defaultLow, for: .horizontal)
        setupButtonRow()
        headerStack.axis = .horizontal
        headerStack.alignment = .center
        headerStack.spacing = 8
        headerStack.addArrangedSubview(titleLabel)
        chrome.axis = .vertical
        sortBar.isHidden = true
        sortBar.onSelect = { [weak self] index in
            self?.onSelectSort?(index)
        }
        addSubviews()
        activateConstraints()
    }

    private func setupButtonRow() {
        buttonStack.axis = .horizontal
        buttonStack.spacing = 20
        buttonStack.translatesAutoresizingMaskIntoConstraints = false
        buttonRow.isHidden = true
        buttonRow.addSubview(buttonStack)
    }

    private func addSubviews() {
        for item in [chrome, list] {
            item.translatesAutoresizingMaskIntoConstraints = false
            addSubview(item)
        }
        for item in [handle, headerStack] {
            item.translatesAutoresizingMaskIntoConstraints = false
            dragRegion.addSubview(item)
        }
        chrome.addArrangedSubview(dragRegion)
        chrome.addArrangedSubview(buttonRow)
        chrome.addArrangedSubview(sortBar)
    }

    private func activateButtonRowConstraints() {
        NSLayoutConstraint.activate([
            buttonStack.leadingAnchor.constraint(
                equalTo: buttonRow.leadingAnchor, constant: 16
            ),
            buttonStack.topAnchor.constraint(equalTo: buttonRow.topAnchor),
            buttonStack.bottomAnchor.constraint(
                equalTo: buttonRow.bottomAnchor, constant: -12
            ),
            buttonStack.heightAnchor.constraint(equalToConstant: 36)
        ])
    }

    private func activateConstraints() {
        activateButtonRowConstraints()
        NSLayoutConstraint.activate([
            chrome.topAnchor.constraint(equalTo: topAnchor),
            chrome.leadingAnchor.constraint(equalTo: leadingAnchor),
            chrome.trailingAnchor.constraint(equalTo: trailingAnchor),

            handle.topAnchor.constraint(equalTo: dragRegion.topAnchor, constant: 8),
            handle.centerXAnchor.constraint(equalTo: dragRegion.centerXAnchor),
            handle.widthAnchor.constraint(equalToConstant: 36),
            handle.heightAnchor.constraint(equalToConstant: 5),

            headerStack.topAnchor.constraint(equalTo: handle.bottomAnchor, constant: 10),
            headerStack.leadingAnchor.constraint(
                equalTo: dragRegion.leadingAnchor, constant: 16
            ),
            headerStack.trailingAnchor.constraint(
                equalTo: dragRegion.trailingAnchor, constant: -16
            ),
            headerStack.bottomAnchor.constraint(equalTo: dragRegion.bottomAnchor, constant: -10),

            list.topAnchor.constraint(equalTo: chrome.bottomAnchor),
            list.leadingAnchor.constraint(equalTo: leadingAnchor),
            list.trailingAnchor.constraint(equalTo: trailingAnchor)
        ])
        // Not required: while the panel is animating off-screen its height
        // goes to zero, and the handle-plus-header chain above genuinely
        // cannot compress. The table reaching the bottom is the constraint
        // that should yield in that transient, so say so rather than let
        // UIKit pick one to break and log about it.
        let tableBottom = list.bottomAnchor.constraint(equalTo: bottomAnchor)
        tableBottom.priority = UILayoutPriority(999)
        tableBottom.isActive = true
    }
}

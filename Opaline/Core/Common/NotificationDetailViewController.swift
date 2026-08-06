import UIKit

/// Full text of a single inbox notification, with an optional "open link"
/// action when the notification carries a URL.
final class NotificationDetailViewController: UIViewController {
    private let item: AppNotification

    private let scrollView = UIScrollView()
    private let titleLabel: UILabel = {
        let label = UILabel()
        label.numberOfLines = 0
        label.font = UIFont.boldSystemFont(ofSize: 20)
        return label
    }()
    private let dateLabel: UILabel = {
        let label = UILabel()
        label.numberOfLines = 1
        label.font = UIFont.systemFont(ofSize: 13)
        return label
    }()
    private let bodyLabel: UITextView = {
        let textView = UITextView()
        LinkifiedText.configure(textView)
        textView.font = UIFont.systemFont(ofSize: 15)
        return textView
    }()

    private var hasLink: Bool {
        guard let urlString = item.urlString else {
            return false
        }
        return URL(string: urlString) != nil
    }

    init(item: AppNotification) {
        self.item = item
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "notifications.title".localized
        setupNavigationItems()
        if hasLink {
            // The link lives on the title instead of a bar button — the
            // sheet's top-right slot belongs to Done.
            titleLabel.isUserInteractionEnabled = true
            titleLabel.addGestureRecognizer(
                UITapGestureRecognizer(target: self, action: #selector(openLink))
            )
        }
        titleLabel.text = item.title
        dateLabel.text = DateFormatter.notificationDetailDisplay.string(from: item.date)
        bodyLabel.delegate = self
        bodyLabel.isHidden = item.body == nil
        setupLayout()
        applyTheme()
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(applyTheme),
            name: ThemeManager.didChangeNotification,
            object: nil
        )
    }

    private func setupNavigationItems() {
        navigationItem.rightBarButtonItem = UIBarButtonItem(
            title: "common.done".localized,
            style: .done,
            target: self,
            action: #selector(dismissSheet)
        )
        // Set explicitly rather than relying on the push-time chevron:
        // Done occupies the right slot, so the way back to the list must
        // exist on every iOS version.
        navigationItem.hidesBackButton = true
        navigationItem.leftBarButtonItem = NavChevron.barButton(
            kind: .back,
            target: self,
            action: #selector(popSelf)
        )
    }

    private func setupLayout() {
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(scrollView)
        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])

        let stack = UIStackView(arrangedSubviews: [titleLabel, dateLabel, bodyLabel])
        stack.axis = .vertical
        stack.spacing = 8
        stack.translatesAutoresizingMaskIntoConstraints = false
        scrollView.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: scrollView.topAnchor, constant: 20),
            stack.leadingAnchor.constraint(equalTo: scrollView.leadingAnchor, constant: 20),
            stack.trailingAnchor.constraint(equalTo: scrollView.trailingAnchor, constant: -20),
            stack.bottomAnchor.constraint(equalTo: scrollView.bottomAnchor, constant: -20),
            stack.widthAnchor.constraint(equalTo: scrollView.widthAnchor, constant: -40)
        ])
    }

    @objc
    private func applyTheme() {
        let theme = ThemeManager.shared
        view.backgroundColor = theme.background
        scrollView.backgroundColor = theme.background
        titleLabel.textColor = hasLink ? theme.accent : theme.primaryText
        dateLabel.textColor = theme.secondaryText
        bodyLabel.attributedText = LinkifiedText.attributedString(
            from: item.body ?? "",
            font: UIFont.systemFont(ofSize: 15),
            color: theme.primaryText,
            includeTimestamps: false
        )
        bodyLabel.linkTextAttributes = [.foregroundColor: theme.accent]
    }

    @objc
    private func popSelf() {
        navigationController?.popViewController(animated: true)
    }

    @objc
    private func dismissSheet() {
        dismiss(animated: true)
    }

    @objc
    private func openLink() {
        guard let urlString = item.urlString, let url = URL(string: urlString) else {
            return
        }
        LinkifiedText.handleTap(url: url)
    }
}

extension NotificationDetailViewController: UITextViewDelegate {
    func textView(
        _ textView: UITextView,
        shouldInteractWith URL: URL,
        in characterRange: NSRange,
        interaction: UITextItemInteraction
    ) -> Bool {
        LinkifiedText.handleTap(url: URL)
    }
}

private extension DateFormatter {
    static let notificationDetailDisplay: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .long
        formatter.timeStyle = .short
        return formatter
    }()
}

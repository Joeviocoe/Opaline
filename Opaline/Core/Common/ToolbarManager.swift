import UIKit

/// Redrawing these ran once per cell instance, so a screen filling up cost
/// ~20 offscreen draws. Callers are all cell/button setup on the main
/// thread, so a plain dictionary needs no lock.
private var resizedNavBarIconCache: [String: UIImage] = [:]

/// Nav-bar icons are PNG assets drawn at their point size and tinted by the
/// bar; shared with `NotificationsBellButton`.
func resizedNavBarIcon(_ name: String, size: CGFloat) -> UIImage? {
    let key = "\(name)@\(size)"
    if let cached = resizedNavBarIconCache[key] {
        return cached
    }
    guard let img = UIImage(named: name) else {
        return nil
    }
    let renderer = UIGraphicsImageRenderer(size: CGSize(width: size, height: size))
    let resized = renderer.image { _ in
        img.draw(in: CGRect(origin: .zero, size: CGSize(width: size, height: size)))
    }
    .withRenderingMode(.alwaysTemplate)
    resizedNavBarIconCache[key] = resized
    return resized
}

/// Builds and manages the shared navigation bar buttons (Search + Settings + Profile/Avatar).
/// Call `install(in:)` from any UIViewController that needs them.
final class ToolbarManager {
    static let shared = ToolbarManager()

    var searchViewControllerFactory: (() -> SearchViewController)?

    private init() {}

    // MARK: - Install buttons in a view controller

    func install(in vc: UIViewController) {
        let searchBtn = UIBarButtonItem(
            image: resizedNavBarIcon("icon_Magnifyingglass", size: 22),
            style: .plain,
            target: vc,
            action: #selector(UIViewController.toolbarOpenSearch)
        )

        let settingsBtn = UIBarButtonItem(
            image: resizedNavBarIcon("icon_Gear", size: 22),
            style: .plain,
            target: vc,
            action: #selector(UIViewController.toolbarOpenSettings)
        )

        let profileBtn = makeProfileButton(
            target: vc,
            action: #selector(UIViewController.toolbarOpenProfile)
        )

        vc.navigationItem.rightBarButtonItems = [profileBtn, settingsBtn, searchBtn]
        vc.navigationItem.leftBarButtonItem = makeBellButton(
            target: vc,
            action: #selector(UIViewController.toolbarOpenNotifications)
        )
        NotificationCenter.default.addObserver(
            vc,
            selector: #selector(UIViewController.toolbarRefreshProfileButton),
            name: UserProfileStore.didUpdateNotification,
            object: nil
        )
    }

    private func makeProfileButton(target: AnyObject, action: Selector) -> UIBarButtonItem {
        let button = ProfileAvatarButton()
        button.refresh()
        button.addTarget(target, action: action, for: .touchUpInside)
        button.addTapFeedback()
        return UIBarButtonItem(customView: button)
    }

    private func makeBellButton(target: AnyObject, action: Selector) -> UIBarButtonItem {
        let button = NotificationsBellButton()
        button.addTarget(target, action: action, for: .touchUpInside)
        button.addTapFeedback()
        return UIBarButtonItem(customView: button)
    }
}

// MARK: - UIViewController extension for toolbar actions

extension UIViewController {
    @objc
    func toolbarOpenSearch() {
        // System bar items expose no view to animate, so these three get the
        // haptic only; the custom bell/avatar buttons pop as well.
        Feedback.tap()
        let searchVC = ToolbarManager.shared.searchViewControllerFactory?()
        guard let searchVC else {
            assertionFailure("ToolbarManager search factory is not configured")
            return
        }
        navigationController?.pushViewController(searchVC, animated: true)
    }

    @objc
    func toolbarOpenNotifications() {
        NotificationsViewController.present(from: self)
    }

    @objc
    func toolbarOpenSettings() {
        Feedback.tap()
        let nav = RotatingNavigationController(rootViewController: SettingsViewController())
        nav.modalPresentationStyle = .pageSheet
        if #available(iOS 15, *) {
            if let sheet = nav.sheetPresentationController {
                sheet.detents = [.medium(), .large()]
                sheet.prefersGrabberVisible = true
            }
        }
        present(nav, animated: true)
    }

    @objc
    func toolbarOpenProfile() {
        if OAuthClient.shared.isSignedIn {
            showSignedInSheet()
        } else {
            showSignedOutSheet()
        }
    }

    @objc
    func toolbarRefreshProfileButton() {
        for item in navigationItem.rightBarButtonItems ?? [] {
            (item.customView as? ProfileAvatarButton)?.refresh()
        }
    }
}

// MARK: - AppDelegate helpers

extension AppDelegate {
    @objc
    func showAuth() {
        DispatchQueue.main.async { [weak self] in
            guard let window = self?.window else {
                return
            }
            // A background fetch can start the app while the device is
            // locked, where "signed out" may just mean the keychain was
            // unreadable. Nobody is looking at the UI anyway — re-decide
            // once the app is actually shown.
            guard UIApplication.shared.applicationState != .background else {
                self?.deferredAuthPresentation = true
                AppLog.auth("sign-in deferred: app is in the background")
                return
            }
            let auth = AuthViewController()
            auth.onAuthorized = { [weak self] in
                UserProfileStore.shared.load()
                self?.showMain()
            }
            auth.onContinueAnonymously = { [weak self] in
                self?.showMain()
            }
            if let presented = window.rootViewController?.presentedViewController {
                presented.dismiss(animated: false) {
                    window.rootViewController = auth
                }
            } else {
                window.rootViewController = auth
            }
        }
    }
}

// MARK: - Profile Avatar Button

final class ProfileAvatarButton: UIButton {
    private let size: CGFloat = 30

    override init(frame: CGRect) {
        super.init(frame: CGRect(x: 0, y: 0, width: 30, height: 30))
        layer.cornerRadius = size / 2
        clipsToBounds = true
        contentMode = .scaleAspectFill
        imageView?.contentMode = .scaleAspectFill
        setImage(defaultImage(), for: .normal)
        tintColor = ThemeManager.shared.isDark ? .white : .darkGray
        translatesAutoresizingMaskIntoConstraints = false
        widthAnchor.constraint(equalToConstant: size).isActive = true
        heightAnchor.constraint(equalToConstant: size).isActive = true
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(refresh),
            name: ThemeManager.didChangeNotification,
            object: nil
        )
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    @objc
    func refresh() {
        tintColor = ThemeManager.shared.isDark ? .white : .darkGray
        if let avatar = UserProfileStore.shared.avatarImage {
            setImage(avatar, for: .normal)
        } else {
            setImage(defaultImage(), for: .normal)
        }
    }

    private func defaultImage() -> UIImage? {
        if let asset = UIImage(named: "icon_person_fill") {
            return asset
        }
        if #available(iOS 13, *) {
            let config = UIImage.SymbolConfiguration(pointSize: size, weight: .light)
            return UIImage(
                systemName: "person.circle.fill",
                withConfiguration: config
            )
        }
        let color = ThemeManager.shared.isDark ? UIColor.white : UIColor.darkGray
        return drawPersonPlaceholder(color: color)
    }

    private func drawPersonPlaceholder(color: UIColor) -> UIImage {
        let side = size
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: side, height: side))
        return renderer.image { ctx in
            let cgCtx = ctx.cgContext
            color.setStroke()
            color.withAlphaComponent(0.25).setFill()
            cgCtx.setLineWidth(1.5)
            cgCtx.addEllipse(in: CGRect(x: 1, y: 1, width: side - 2, height: side - 2))
            cgCtx.drawPath(using: .fillStroke)
            color.setFill()
            let headR = side * 0.22
            let headRect = CGRect(
                x: side / 2 - headR,
                y: side * 0.2,
                width: headR * 2,
                height: headR * 2
            )
            cgCtx.fillEllipse(in: headRect)
            let bodyR = side * 0.32
            let bodyRect = CGRect(
                x: side / 2 - bodyR,
                y: side * 0.52,
                width: bodyR * 2,
                height: bodyR * 2
            )
            cgCtx.addEllipse(in: bodyRect)
            cgCtx.clip()
            cgCtx.fill(CGRect(x: 0, y: 0, width: side, height: side))
        }
        .withRenderingMode(.alwaysOriginal)
    }
}

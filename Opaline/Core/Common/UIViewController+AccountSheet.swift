import UIKit

// MARK: - Account sheet

extension UIViewController {
    private static func performSignOut() {
        OAuthClient.shared.signOut()
        UserProfileStore.shared.clear()
        AppCache.shared.clearHomeFeed()
        NotificationCenter.default.post(
            name: .userDidSignOut,
            object: nil
        )
        (UIApplication.shared.delegate as? AppDelegate)?.showAuth()
    }

    func showSignedInSheet() {
        let name = UserProfileStore.shared.displayName
            ?? "account.fallbackName".localized
        let sheet = UIAlertController(
            title: name,
            message: nil,
            preferredStyle: .actionSheet
        )
        if let channelId = UserDefaults.standard.string(
            forKey: UserDefaultsKeys.Account.ownChannelId
        ) {
            sheet.addAction(UIAlertAction(
                title: "account.myChannel".localized,
                style: .default
            ) { [weak self] _ in
                self?.openOwnChannel(id: channelId, name: name)
            })
        }
        sheet.addAction(UIAlertAction(
            title: "account.signOut".localized,
            style: .destructive
        ) { _ in
            Self.performSignOut()
        })
        sheet.addAction(UIAlertAction(title: "common.cancel".localized, style: .cancel))
        configurePopover(sheet)
        present(sheet, animated: true)
    }

    private func openOwnChannel(id: String, name: String) {
        guard let factory = VideoRouter.shared
            .channelViewControllerFactory
        else {
            return
        }
        navigationController?.pushViewController(
            factory(id, name),
            animated: true
        )
    }

    func showSignedOutSheet() {
        let sheet = UIAlertController(
            title: "account.notSignedIn".localized,
            message: nil,
            preferredStyle: .actionSheet
        )
        sheet.addAction(UIAlertAction(
            title: "account.signIn".localized,
            style: .default
        ) { _ in
            (UIApplication.shared.delegate as? AppDelegate)?.showAuth()
        })
        sheet.addAction(UIAlertAction(title: "common.cancel".localized, style: .cancel))
        configurePopover(sheet)
        present(sheet, animated: true)
    }

    private func configurePopover(_ alert: UIAlertController) {
        if let pop = alert.popoverPresentationController {
            if let btn = navigationItem.rightBarButtonItems?.first(where: {
                $0.customView is ProfileAvatarButton
            }) {
                pop.barButtonItem = btn
            } else {
                pop.sourceView = view
                pop.sourceRect = CGRect(
                    x: view.bounds.midX,
                    y: view.bounds.midY,
                    width: 0,
                    height: 0
                )
                pop.permittedArrowDirections = []
            }
        }
    }
}

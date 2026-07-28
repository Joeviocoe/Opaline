import UIKit
import UserNotifications

/// Legacy background fetch (single code path for iOS 12…latest — see
/// `configureLegacyBackgroundFetch`) and notification-tap handling.
extension AppDelegate {
    /// `@objc` is explicit: this is an optional protocol requirement
    /// implemented in an extension, and UIKit finds it through the ObjC
    /// runtime — without the attribute a silent miss is very hard to spot.
    @objc
    @available(iOS, deprecated: 13.0, message: "Single code path for iOS 12+.")
    func application(
        _ application: UIApplication,
        performFetchWithCompletionHandler completionHandler:
            @escaping (UIBackgroundFetchResult) -> Void
    ) {
        AppLog.notifications("background fetch woke the app")
        // `force`: the 2h throttle exists to keep foreground launches from
        // hammering the manifest. iOS hands out these windows sparingly and
        // on its own schedule, so throttling one would just waste it.
        UpdateNotificationService.shared.checkIfNeeded(force: true) { added in
            AppLog.notifications("background fetch finished: newData=\(added)")
            completionHandler(added ? .newData : .noData)
        }
    }
}

extension AppDelegate: UNUserNotificationCenterDelegate {
    /// Show the banner even while the app is in the foreground: an inbox
    /// entry can land during a background fetch that iOS runs with the app
    /// still on screen, and a silently-updated bell reads as "nothing
    /// happened".
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler:
            @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        AppLog.notifications("presenting banner in the foreground")
        if #available(iOS 14.0, *) {
            completionHandler([.banner, .list])
        } else {
            completionHandler([.alert])
        }
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        DispatchQueue.main.async { [weak self] in
            if let presenter = self?.topPresentableViewController() {
                NotificationsViewController.present(from: presenter)
            }
            completionHandler()
        }
    }

    private func topPresentableViewController() -> UIViewController? {
        guard let root = window?.rootViewController,
              !(root is AuthViewController),
              !(root is SplashViewController)
        else { return nil }
        var top = root
        while let presented = top.presentedViewController {
            top = presented
        }
        return top
    }
}

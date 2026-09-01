import UIKit

#if LEGACY_IOS9
// The UserNotifications framework is iOS 10. Shadowing the handful of names the
// app actually uses keeps every call site unchanged.
//
// This is backed by UILocalNotification rather than stubbed out, so update
// banners genuinely work on iOS 9 -- the plan's fallback was a no-op, and a
// working banner costs about the same.
//
// Known limitation: iOS 9 reports the authorization result through
// application(_:didRegister:), not through a completion handler, so
// requestAuthorization reports the settings as they stand just after
// registering. The first call therefore returns false while the system prompt
// is still on screen; the next one returns the real answer.

enum UNAuthorizationStatus: Int {
    case notDetermined = 0, denied = 1, authorized = 2, provisional = 3, ephemeral = 4
}

struct UNAuthorizationOptions: OptionSet {
    let rawValue: UInt
    init(rawValue: UInt) { self.rawValue = rawValue }
    static let badge = UNAuthorizationOptions(rawValue: 1 << 0)
    static let sound = UNAuthorizationOptions(rawValue: 1 << 1)
    static let alert = UNAuthorizationOptions(rawValue: 1 << 2)
}

struct UNNotificationPresentationOptions: OptionSet {
    let rawValue: UInt
    init(rawValue: UInt) { self.rawValue = rawValue }
    static let badge = UNNotificationPresentationOptions(rawValue: 1 << 0)
    static let sound = UNNotificationPresentationOptions(rawValue: 1 << 1)
    static let alert = UNNotificationPresentationOptions(rawValue: 1 << 2)
    static let banner = UNNotificationPresentationOptions(rawValue: 1 << 3)
    static let list = UNNotificationPresentationOptions(rawValue: 1 << 4)
}

struct UNNotificationSettings {
    let authorizationStatus: UNAuthorizationStatus
}

class UNNotificationContent {
    var title = ""
    var body = ""
    var userInfo: [AnyHashable: Any] = [:]
}

final class UNMutableNotificationContent: UNNotificationContent {}

class UNNotificationTrigger {}

final class UNNotificationRequest {
    let identifier: String
    let content: UNNotificationContent
    let trigger: UNNotificationTrigger?

    init(identifier: String, content: UNNotificationContent, trigger: UNNotificationTrigger?) {
        self.identifier = identifier
        self.content = content
        self.trigger = trigger
    }
}

final class UNNotification {
    let request: UNNotificationRequest
    init(request: UNNotificationRequest) { self.request = request }
}

final class UNNotificationResponse {
    let notification: UNNotification
    init(notification: UNNotification) { self.notification = notification }
}

protocol UNUserNotificationCenterDelegate: AnyObject {
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    )
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    )
}

// iOS 9 routes taps through application(_:didReceive:), so neither is called
// here; defaults keep conformance from forcing dead implementations.
extension UNUserNotificationCenterDelegate {
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) { completionHandler([]) }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) { completionHandler() }
}

final class UNUserNotificationCenter {
    private static let shared = UNUserNotificationCenter()
    static func current() -> UNUserNotificationCenter { shared }

    weak var delegate: UNUserNotificationCenterDelegate?

    private var currentStatus: UNAuthorizationStatus {
        guard let settings = UIApplication.shared.currentUserNotificationSettings else {
            return .notDetermined
        }
        return settings.types.isEmpty ? .denied : .authorized
    }

    func getNotificationSettings(
        completionHandler: @escaping (UNNotificationSettings) -> Void
    ) {
        let status = currentStatus
        DispatchQueue.main.async {
            completionHandler(UNNotificationSettings(authorizationStatus: status))
        }
    }

    func requestAuthorization(
        options: UNAuthorizationOptions = [],
        completionHandler: @escaping (Bool, Error?) -> Void
    ) {
        var types: UIUserNotificationType = []
        if options.contains(.alert) { types.insert(.alert) }
        if options.contains(.sound) { types.insert(.sound) }
        if options.contains(.badge) { types.insert(.badge) }
        DispatchQueue.main.async {
            UIApplication.shared.registerUserNotificationSettings(
                UIUserNotificationSettings(types: types, categories: nil)
            )
            completionHandler(self.currentStatus == .authorized, nil)
        }
    }

    func add(
        _ request: UNNotificationRequest,
        withCompletionHandler completionHandler: ((Error?) -> Void)? = nil
    ) {
        DispatchQueue.main.async {
            let notification = UILocalNotification()
            notification.alertTitle = request.content.title
            notification.alertBody = request.content.body
            notification.userInfo = request.content.userInfo
            notification.soundName = UILocalNotificationDefaultSoundName
            // No trigger means "now", which is the only form used here.
            UIApplication.shared.presentLocalNotificationNow(notification)
            completionHandler?(nil)
        }
    }

    func removeAllDeliveredNotifications() {
        UIApplication.shared.cancelAllLocalNotifications()
    }
}
#endif

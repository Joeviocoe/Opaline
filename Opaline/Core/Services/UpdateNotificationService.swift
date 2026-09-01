import Foundation
import UserNotifications

/// Checks the release manifest for a newer app version and, when found,
/// appends an entry to the notification inbox (and mirrors it as a system
/// notification, when allowed).
final class UpdateNotificationService {
    static let shared = UpdateNotificationService()

    /// Master toggle for update checks; default on.
    static var updatesEnabled: Bool {
        get {
            let key = UserDefaultsKeys.Notifications.appUpdatesEnabled
            let exists = UserDefaults.standard.object(forKey: key) != nil
            return exists ? UserDefaults.standard.bool(forKey: key) : true
        }
        set {
            UserDefaults.standard.set(
                newValue,
                forKey: UserDefaultsKeys.Notifications.appUpdatesEnabled
            )
        }
    }

    /// Foreground poll interval. Background wake-ups pass `force` — iOS
    /// hands those out rarely enough that throttling them wastes a window.
    private static let throttleInterval: TimeInterval = 2 * 60 * 60

    /// Announcements (news entries without a `release-` prefix) older than
    /// this are skipped, so a fresh install doesn't inherit the whole
    /// historical feed at once. Release entries are filtered by version
    /// instead and ignore this.
    static let maxAnnouncementAge: TimeInterval = 30 * 24 * 60 * 60

    private let transport: HTTPTransport
    private let dateFormatter = ISO8601DateFormatter()

    init(transport: HTTPTransport = ServiceContainer.mediaTransport) {
        self.transport = transport
    }

    /// Fetches the manifest and appends any relevant `AppNotification`.
    /// Throttled to `throttleInterval` unless `force`.
    /// `completion(true)` when a new inbox item was added. Fires on main queue.
    func checkIfNeeded(force: Bool = false, completion: ((Bool) -> Void)? = nil) {
        guard UpdateNotificationService.updatesEnabled else {
            AppLog.notifications("check skipped: disabled")
            completion?(false)
            return
        }
        guard force || isThrottleElapsed() else {
            AppLog.notifications("check skipped: throttled, \(throttleStatus())")
            completion?(false)
            return
        }
        guard let url = URL(string: AppURLs.AppManifest.source) else {
            AppLog.notifications("check skipped: bad manifest URL")
            completion?(false)
            return
        }
        fetchManifest(from: url, completion: completion)
    }
}

private extension UpdateNotificationService {
    func fetchManifest(from url: URL, completion: ((Bool) -> Void)?) {
        AppLog.notifications("fetching \(url.absoluteString)")
        let request = HTTPRequest(method: .get, url: url, sendsCookies: false)
        transport.send(request, cancellationToken: nil) { [weak self] result in
            guard let self = self else {
                return
            }
            UserDefaults.standard.set(
                Date(),
                forKey: UserDefaultsKeys.Notifications.lastUpdateCheck
            )
            switch result {
            case .success(let response):
                AppLog.notifications(
                    "fetched: HTTP \(response.status), \(response.data.count)b"
                )
                self.handleManifest(response.data, completion: completion)
            case .failure(let error):
                AppLog.notifications("fetch failed: \(error)")
                DispatchQueue.main.async { completion?(false) }
            }
        }
    }

    /// "17m left of 120m" — makes a skipped check self-explanatory in the log.
    func throttleStatus() -> String {
        let interval = UpdateNotificationService.throttleInterval
        let last = UserDefaults.standard.object(
            forKey: UserDefaultsKeys.Notifications.lastUpdateCheck
        ) as? Date
        let elapsed = last.map { Date().timeIntervalSince($0) } ?? 0
        let left = Int((interval - elapsed) / 60)
        return "\(left)m left of \(Int(interval / 60))m"
    }

    func isThrottleElapsed() -> Bool {
        guard let last = UserDefaults.standard.object(
            forKey: UserDefaultsKeys.Notifications.lastUpdateCheck
        ) as? Date else {
            return true
        }
        let interval = UpdateNotificationService.throttleInterval
        return Date().timeIntervalSince(last) >= interval
    }

    func handleManifest(_ data: Data, completion: ((Bool) -> Void)?) {
        guard let json = try? JSONSerialization.jsonObject(with: data),
              let root = json as? [String: Any],
              let apps = root["apps"] as? [[String: Any]],
              let versions = apps.first?["versions"] as? [[String: Any]]
        else {
            AppLog.notifications("manifest parse failed")
            DispatchQueue.main.async { completion?(false) }
            return
        }
        let currentVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"]
            as? String ?? "0"
        // Oldest first, so the newest entry ends up on top of the inbox.
        let items = (root["news"] as? [[String: Any]] ?? [])
            .reversed()
            .compactMap {
                buildNotification($0, versions: versions, currentVersion: currentVersion)
            }
        AppLog.notifications(
            "manifest: news=\((root["news"] as? [[String: Any]] ?? []).count) "
                + "relevant=\(items.count) current=\(currentVersion)"
        )
        storeAndSchedule(items, completion: completion)
    }

    func storeAndSchedule(_ items: [AppNotification], completion: ((Bool) -> Void)?) {
        DispatchQueue.main.async {
            let added = items.filter { AppNotificationStore.shared.add($0) }
            for item in added {
                AppLog.notifications("new notification: \(item.id)")
            }
            // A backlog can add several at once; only the newest is worth a
            // system banner.
            if let newest = added.last {
                self.scheduleSystemNotificationIfAllowed(newest)
            }
            completion?(!added.isEmpty)
        }
    }

    /// A `release-<version>` entry is an update announcement: relevant only
    /// when that version is newer than the running one, and its body comes
    /// from the matching release notes (the news `caption` is truncated with
    /// an ellipsis in the manifest). Anything else is a standalone
    /// announcement that always reaches the inbox.
    func buildNotification(
        _ entry: [String: Any],
        versions: [[String: Any]],
        currentVersion: String
    ) -> AppNotification? {
        guard let id = entry["identifier"] as? String else {
            return nil
        }
        let date = (entry["date"] as? String).flatMap(dateFormatter.date(from:)) ?? Date()
        // Anything published before this build was installed is history the
        // user never asked for — a fresh install starts with an empty inbox.
        guard date >= featureInstallDate() else {
            return nil
        }
        var body = entry["caption"] as? String
        var fallbackTitle = id
        if let version = releaseVersion(from: id) {
            guard isVersion(version, greaterThan: currentVersion) else {
                return nil
            }
            body = releaseNotes(for: version, in: versions) ?? body
            fallbackTitle = String(
                format: "notifications.update.title".localized,
                version
            )
        } else if isStaleAnnouncement(date) {
            return nil
        }
        return AppNotification(
            id: id,
            title: entry["title"] as? String ?? fallbackTitle,
            body: body,
            date: date,
            urlString: entry["url"] as? String,
            isRead: false
        )
    }

    func releaseNotes(for version: String, in versions: [[String: Any]]) -> String? {
        let match = versions.first { ($0["version"] as? String) == version }
        guard let notes = match?["localizedDescription"] as? String else {
            return nil
        }
        let flattened = plainText(notes)
        return flattened.isEmpty ? nil : flattened
    }

    func scheduleSystemNotificationIfAllowed(_ item: AppNotification) {
        SystemNotificationAuthorization.status { status in
            guard status == .authorized else {
                AppLog.notifications("system banner skipped: authorization \(status.rawValue)")
                return
            }
            let content = UNMutableNotificationContent()
            content.title = item.title
            if let body = item.body {
                content.body = body
            }
            let request = UNNotificationRequest(
                identifier: item.id,
                content: content,
                trigger: nil
            )
            UNUserNotificationCenter.current().add(request) { error in
                if let error = error {
                    AppLog.notifications("local notification failed: \(error)")
                }
            }
        }
    }
}

/// System notification authorization, usable by the UI to prompt the user.
enum SystemNotificationAuthorization {
    static func status(_ completion: @escaping (UNAuthorizationStatus) -> Void) {
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            DispatchQueue.main.async {
                completion(settings.authorizationStatus)
            }
        }
    }

    static func request(_ completion: @escaping (Bool) -> Void) {
        UNUserNotificationCenter.current().requestAuthorization(
            options: [.alert, .sound, .badge]
        ) { granted, _ in
            DispatchQueue.main.async {
                completion(granted)
            }
        }
    }
}

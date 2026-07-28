import Foundation

/// One entry in the in-app notification inbox.
struct AppNotification: Codable {
    let id: String
    let title: String
    let body: String?
    let date: Date
    let urlString: String?
    var isRead: Bool
}

/// Plain-file (JSON) backed store for the in-app notification inbox.
/// Public API is main-thread only.
final class AppNotificationStore {
    static let shared = AppNotificationStore()
    static let didChangeNotification = Notification.Name("AppNotificationStoreDidChange")

    private static let maxStored = 50
    private static let fileName = "notifications.json"
    private let ioQueue = DispatchQueue(label: "com.verback.YTLite.AppNotificationStore.io")

    private var loaded = false
    private var storage: [AppNotification] = []

    var notifications: [AppNotification] {
        loadIfNeeded()
        return storage
    }

    var unreadCount: Int {
        notifications.filter { !$0.isRead }.count
    }

    private init() {}

    @discardableResult
    func add(_ item: AppNotification) -> Bool {
        loadIfNeeded()
        guard !storage.contains(where: { $0.id == item.id }) else {
            return false
        }
        storage.insert(item, at: 0)
        if storage.count > AppNotificationStore.maxStored {
            storage.removeLast(storage.count - AppNotificationStore.maxStored)
        }
        persistAndNotify()
        return true
    }

    func markRead(id: String) {
        loadIfNeeded()
        guard let index = storage.firstIndex(where: { $0.id == id }), !storage[index].isRead
        else {
            return
        }
        storage[index].isRead = true
        persistAndNotify()
    }

    func markAllRead() {
        loadIfNeeded()
        guard storage.contains(where: { !$0.isRead }) else {
            return
        }
        for index in storage.indices {
            storage[index].isRead = true
        }
        persistAndNotify()
    }

    func remove(id: String) {
        loadIfNeeded()
        guard let index = storage.firstIndex(where: { $0.id == id }) else {
            return
        }
        storage.remove(at: index)
        persistAndNotify()
    }

    func clear() {
        loadIfNeeded()
        guard !storage.isEmpty else {
            return
        }
        storage = []
        persistAndNotify()
    }
}

// MARK: - Persistence

private extension AppNotificationStore {
    var fileURL: URL {
        let dir = FileManager.default.urls(
            for: .applicationSupportDirectory, in: .userDomainMask
        )[0]
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent(AppNotificationStore.fileName)
    }

    func loadIfNeeded() {
        guard !loaded else {
            return
        }
        loaded = true
        guard let data = try? Data(contentsOf: fileURL),
              let decoded = try? JSONDecoder().decode([AppNotification].self, from: data)
        else {
            return
        }
        storage = decoded
    }

    func persistAndNotify() {
        let snapshot = storage
        let url = fileURL
        ioQueue.async {
            guard let data = try? JSONEncoder().encode(snapshot) else {
                return
            }
            // Background fetch runs while the device is locked; the default
            // `.complete` protection would make this write fail there and
            // lose the entry.
            try? data.write(
                to: url,
                options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication]
            )
        }
        DispatchQueue.main.async {
            NotificationCenter.default.post(
                name: AppNotificationStore.didChangeNotification,
                object: nil
            )
        }
    }
}

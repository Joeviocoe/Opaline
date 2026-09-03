import UIKit

/// Videos watched on this device, with no account.
///
/// Modelled on `WatchProgressStore` because it is written during playback:
/// an `NSLock` around the array and its index, never touching the file layer
/// or `NotificationCenter` while holding it, and a debounced persist on a
/// serial queue.
///
/// The one thing it adds is a **synchronous flush on
/// `didEnterBackground`**: an iPad 3 is jetsammed while suspended
/// routinely, and that flush is the whole reason "I watched it, then the app
/// died" survives.
final class LocalHistoryStore {
    static let shared = LocalHistoryStore()
    static let didChangeNotification = Notification.Name(
        "LocalHistoryStoreDidChange"
    )

    private static let fileName = "history.json"
    private let persistDebounceInterval: TimeInterval = 5

    /// Guards `entries` and `index`.
    private let lock = NSLock()
    /// Newest first, so eviction is `removeLast` — oldest-first, unlike
    /// `WatchProgressStore.trimLocked`'s arbitrary `keys.prefix`.
    private var entries: [LocalHistoryEntry] = []
    private var index: Set<String> = []
    private var loaded = false
    private var isReadOnly = false
    /// Set by every mutation, cleared by a successful write. The background
    /// flush checks it: without that, an app launched and backgrounded
    /// without ever touching history would flush an empty, never-loaded
    /// array straight over a real file.
    private var dirty = false

    private let persistQueue = DispatchQueue(
        label: "com.ytvlite.local-history.persist"
    )
    /// Only touched on `persistQueue`.
    private var pendingWork: DispatchWorkItem?

    private init() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(appDidEnterBackground),
            name: UIApplication.didEnterBackgroundNotification,
            object: nil
        )
    }

    var videos: [Video] {
        allEntries.map { $0.video }
    }

    var count: Int {
        allEntries.count
    }

    var allEntries: [LocalHistoryEntry] {
        loadIfNeeded()
        lock.lock()
        let snapshot = entries
        lock.unlock()
        return snapshot
    }

    var watchedVideoIds: Set<String> {
        loadIfNeeded()
        lock.lock()
        let snapshot = index
        lock.unlock()
        return snapshot
    }

    /// One entry per video: a re-watch moves it back to the front, which is
    /// what YouTube's own history does.
    func record(_ entry: LocalHistoryEntry) {
        loadIfNeeded()
        let limit = LocalLibraryPreferences.historyLimit
        lock.lock()
        entries.removeAll { $0.videoId == entry.videoId }
        entries.insert(entry, at: 0)
        index.insert(entry.videoId)
        if entries.count > limit {
            let dropped = entries.suffix(entries.count - limit)
            entries.removeLast(entries.count - limit)
            for old in dropped {
                index.remove(old.videoId)
            }
        }
        let total = entries.count
        dirty = true
        lock.unlock()
        AppLog.library(
            "history record \(entry.videoId) '\(entry.title)'"
                + " total=\(total)"
        )
        schedulePersist()
        postDidChange()
    }

    func remove(videoId: String) {
        loadIfNeeded()
        lock.lock()
        entries.removeAll { $0.videoId == videoId }
        index.remove(videoId)
        let total = entries.count
        dirty = true
        lock.unlock()
        AppLog.library("history remove \(videoId) total=\(total)")
        schedulePersist()
        postDidChange()
    }

    func clear() {
        loadIfNeeded()
        lock.lock()
        entries = []
        index = []
        dirty = true
        lock.unlock()
        AppLog.library("history cleared")
        schedulePersist()
        postDidChange()
    }
}

// MARK: - Persistence

private extension LocalHistoryStore {
    func loadIfNeeded() {
        lock.lock()
        let alreadyLoaded = loaded
        loaded = true
        lock.unlock()
        guard !alreadyLoaded else {
            return
        }
        let result = LocalLibraryFile.load(
            LocalHistoryEntry.self,
            fileName: LocalHistoryStore.fileName
        )
        var items: [LocalHistoryEntry] = []
        var readOnly = false
        switch result {
        case .empty:
            items = []
        case .loaded(let stored):
            items = stored
        case .unreadable:
            readOnly = true
        }
        lock.lock()
        entries = items
        index = Set(items.map { $0.videoId })
        isReadOnly = readOnly
        lock.unlock()
    }

    func postDidChange() {
        DispatchQueue.main.async {
            NotificationCenter.default.post(
                name: LocalHistoryStore.didChangeNotification,
                object: nil
            )
        }
    }

    /// At most one write per `persistDebounceInterval` — playback records
    /// while the player is running, and this is the user's only copy.
    func schedulePersist() {
        persistQueue.async { [weak self] in
            guard let self = self, self.pendingWork == nil else {
                return
            }
            let work = DispatchWorkItem { [weak self] in
                guard let self = self else {
                    return
                }
                self.pendingWork = nil
                self.writeToDisk()
            }
            self.pendingWork = work
            self.persistQueue.asyncAfter(
                deadline: .now() + self.persistDebounceInterval,
                execute: work
            )
        }
    }

    /// Must run on `persistQueue`. Copies under the lock, writes outside it.
    func writeToDisk() {
        lock.lock()
        let snapshot = entries
        let readOnly = isReadOnly
        let hasChanges = dirty
        lock.unlock()
        guard !readOnly else {
            AppLog.library("history: write skipped, file unreadable")
            return
        }
        // Nothing changed means nothing to write — and, crucially, a store
        // that was never loaded has nothing to say about what is on disk.
        guard hasChanges else {
            return
        }
        guard LocalLibraryFile.save(
            snapshot, fileName: LocalHistoryStore.fileName
        ) else {
            return
        }
        lock.lock()
        dirty = false
        lock.unlock()
    }

    @objc
    func appDidEnterBackground() {
        // Synchronous: the app can be suspended the moment this handler
        // returns, and on a 1 GB device it is often killed before it wakes
        // again. This is what makes a watch survive a jetsam.
        lock.lock()
        let hasChanges = dirty
        lock.unlock()
        guard hasChanges else {
            return
        }
        let started = Date()
        persistQueue.sync {
            self.pendingWork?.cancel()
            self.pendingWork = nil
            self.writeToDisk()
        }
        let ms = Int(Date().timeIntervalSince(started) * 1_000)
        AppLog.library("history background flush in \(ms)ms")
    }
}

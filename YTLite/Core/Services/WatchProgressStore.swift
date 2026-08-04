import UIKit

struct WatchProgress {
    let fraction: Double

    var shouldShow: Bool {
        fraction > 0.03
    }
}

/// Stores per-video watch progress from YouTube servers.
/// Populated by WatchProgressSyncService and inline
/// extraction from browse/feed responses.
final class WatchProgressStore {
    static let shared = WatchProgressStore()

    private let fractionKey = "WatchProgressStore.fractions"
    private let maxEntries = 200
    private let persistDebounceInterval: TimeInterval = 5

    /// Guards `fractions` only. Never call UserDefaults or
    /// NotificationCenter while holding it.
    private let lock = NSLock()
    private var fractions: [String: Double] = [:]

    /// Serial: all UserDefaults writes and pending-write bookkeeping
    /// happen here, off the lock.
    private let persistQueue = DispatchQueue(
        label: "com.ytvlite.watch-progress.persist"
    )
    /// Only touched from `persistQueue`.
    private var pendingWork: DispatchWorkItem?

    init() {
        loadFractions()
        UserDefaults.standard.removeObject(
            forKey: "WatchProgressStore.v1"
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(appDidEnterBackground),
            name: UIApplication.didEnterBackgroundNotification,
            object: nil
        )
    }

    func setFraction(
        videoId: String,
        fraction: Double
    ) {
        lock.lock()
        fractions[videoId] = fraction
        if fractions.count > maxEntries {
            let excess = fractions.count - maxEntries
            fractions.keys.prefix(excess).forEach {
                fractions.removeValue(forKey: $0)
            }
        }
        lock.unlock()
        schedulePersist()
    }

    func setServerFractions(
        _ entries: [String: Double]
    ) {
        lock.lock()
        fractions = entries
        lock.unlock()
        persistQueue.async {
            self.pendingWork?.cancel()
            self.pendingWork = nil
            self.writeToDefaults()
        }
    }

    func progress(
        forVideoId videoId: String
    ) -> WatchProgress? {
        lock.lock()
        let frac = fractions[videoId]
        lock.unlock()
        guard let frac else {
            return nil
        }
        return WatchProgress(fraction: frac)
    }

    func clearAll() {
        lock.lock()
        fractions.removeAll()
        lock.unlock()
        persistQueue.async {
            self.pendingWork?.cancel()
            self.pendingWork = nil
            UserDefaults.standard.removeObject(
                forKey: self.fractionKey
            )
        }
    }

    // MARK: - Persistence

    private func loadFractions() {
        guard let raw = UserDefaults.standard.dictionary(
            forKey: fractionKey
        ) as? [String: Double]
        else {
            return
        }
        fractions = raw
    }

    /// Throttles UserDefaults writes to at most one per
    /// `persistDebounceInterval`. Safe to call from any thread.
    private func schedulePersist() {
        persistQueue.async {
            guard self.pendingWork == nil else {
                return
            }
            let work = DispatchWorkItem { [weak self] in
                guard let self else {
                    return
                }
                self.pendingWork = nil
                self.writeToDefaults()
            }
            self.pendingWork = work
            self.persistQueue.asyncAfter(
                deadline: .now() + self.persistDebounceInterval,
                execute: work
            )
        }
    }

    /// Must run on `persistQueue`. Copies the dictionary under the
    /// lock, then writes outside it.
    private func writeToDefaults() {
        lock.lock()
        let snapshot = fractions
        lock.unlock()
        UserDefaults.standard.set(snapshot, forKey: fractionKey)
    }

    @objc
    private func appDidEnterBackground() {
        // Synchronous: the app can be suspended right after this
        // handler returns, so the flush must finish before that.
        persistQueue.sync {
            self.pendingWork?.cancel()
            self.pendingWork = nil
            self.writeToDefaults()
        }
    }
}

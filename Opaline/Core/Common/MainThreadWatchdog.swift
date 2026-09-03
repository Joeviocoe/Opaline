import UIKit

/// Detects main-thread stalls using a `CADisplayLink`: its callback firing
/// late IS the measurement — if the main thread is blocked, the callback is
/// delayed by exactly that much. Time Profiler, Hangs, Hitches and
/// MetricKit all record nothing on iOS 12, so this is the only signal
/// available there.
///
/// Off by default (`UserDefaultsKeys.Debug.mainThreadWatchdog`); the per-tick
/// path is kept to a subtraction, two comparisons and an assignment so
/// running it does not itself become a source of jank.
final class MainThreadWatchdog {
    private struct Tally {
        var count = 0
        var totalMs: Double = 0
        var worstMs: Double = 0
    }

    static let shared = MainThreadWatchdog()

    private var displayLink: CADisplayLink?
    private var rootViewControllerProvider: (() -> UIViewController?)?
    /// 0 is the "no previous tick" sentinel — `CACurrentMediaTime()` never
    /// returns 0, so this also doubles as the "just (re)started" flag that
    /// stops the first tick after start/resume from reporting a bogus stall.
    private var lastTimestamp: CFTimeInterval = 0
    private var lifecycleObservers: [NSObjectProtocol] = []

    // Rate limiting: at most this many stall lines per rolling second: a
    // sustained freeze coalesces into one suppressed-count line instead of
    // flooding the log.
    private let maxLogsPerSecond = 3
    /// Floor for reporting a stall at all. **Set to 0 to restore the old
    /// report-every-hitch behaviour** — the detection itself is unchanged,
    /// this only decides what is worth a line.
    ///
    /// Raised rather than tightening the rate limit: the rate limit coalesces
    /// a burst, but a steady drip of 33 ms hitches slips under it all day and
    /// still fills the log.
    private static let minimumReportedStall: CFTimeInterval = 0.25
    /// At or above this, the stall is logged even with verbose off — it is a
    /// freeze somebody noticed, not a hitch. 42 lines in a 9858-line sample.
    private static let alwaysReportedStallMs: Double = 1000
    private var windowStart: CFTimeInterval = 0
    private var loggedInWindow = 0
    private var suppressedInWindow = 0

    // Keyed by resolved screen name — bounded by the number of distinct
    // screen types the app has (a few dozen), not by stall count.
    private var tallies: [String: Tally] = [:]

    private init() {}

    // MARK: - Screen resolution

    /// Walks the visible-view-controller chain: presented VCs, then the
    /// app's container types. Falls back to the leaf's own type name once
    /// nothing more specific can be unwrapped.
    static func resolveScreenName(from root: UIViewController) -> String {
        var current = root
        while true {
            // Checked every iteration, not just at the root: a sheet put up
            // from a screen inside the navigation stack hangs off that
            // screen, so a single pass up front would miss it and report
            // whatever is behind the sheet.
            if let presented = current.presentedViewController {
                current = presented
            } else if let tab = current as? UITabBarController,
               let selected = tab.selectedViewController {
                current = selected
            } else if let nav = current as? UINavigationController,
                      let top = nav.topViewController {
                current = top
            } else if let container = current as? RootContainerViewController,
                      let last = container.children.last {
                current = last
            } else if let panel = current as? PlayerPanelViewController,
                      let wrapper = panel.children.first {
                current = wrapper
            } else {
                break
            }
        }
        return String(describing: type(of: current))
    }

    /// - Parameter rootViewControllerProvider: resolves the window's current
    ///   root view controller on demand. Called only when a stall is
    ///   detected, never on the idle path.
    func start(rootViewControllerProvider: @escaping () -> UIViewController?) {
        guard displayLink == nil else {
            return
        }
        self.rootViewControllerProvider = rootViewControllerProvider
        lastTimestamp = 0
        windowStart = 0
        loggedInWindow = 0
        suppressedInWindow = 0
        attachDisplayLink()
        observeLifecycle()
    }

    /// Logs the session summary, then tears everything down. Safe to call
    /// even if `start` was never called.
    func stop() {
        guard displayLink != nil || rootViewControllerProvider != nil else {
            return
        }
        logSummary()
        detachDisplayLink()
        // Removing tokens rather than `removeObserver(self)`, which the
        // project bans outside `deinit` — this is a singleton that gets
        // started and stopped repeatedly.
        lifecycleObservers.forEach(NotificationCenter.default.removeObserver)
        lifecycleObservers.removeAll()
        rootViewControllerProvider = nil
        tallies.removeAll()
    }

    private func observeLifecycle() {
        let center = NotificationCenter.default
        // The link stops firing while suspended anyway; detaching avoids
        // reporting the whole background period as one enormous stall.
        lifecycleObservers.append(
            center.addObserver(
                forName: UIApplication.didEnterBackgroundNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                self?.detachDisplayLink()
            }
        )
        lifecycleObservers.append(
            center.addObserver(
                forName: UIApplication.willEnterForegroundNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                self?.resumeAfterForeground()
            }
        )
    }

    private func resumeAfterForeground() {
        guard rootViewControllerProvider != nil, displayLink == nil else {
            return
        }
        lastTimestamp = 0
        attachDisplayLink()
    }

    private func attachDisplayLink() {
        let link = CADisplayLink(target: self, selector: #selector(tick(_:)))
        link.add(to: .main, forMode: .common)
        displayLink = link
    }

    private func detachDisplayLink() {
        displayLink?.invalidate()
        displayLink = nil
    }

    // MARK: - Hot path

    @objc
    private func tick(_ link: CADisplayLink) {
        guard lastTimestamp > 0 else {
            lastTimestamp = link.timestamp
            return
        }
        let delta = link.timestamp - lastTimestamp
        lastTimestamp = link.timestamp
        // `duration` is only meaningful once a frame has actually been sent;
        // it reads 0 before then, which would make the threshold 0 and turn
        // every single tick into a reported stall.
        let frame = link.duration
        // Two frames (~33 ms) reported every hitch: 1385 lines in one
        // session, almost all of them 33-183 ms and not actionable. The
        // stalls that have mattered on this hardware were 20-60 SECONDS, and
        // AppLog rotates at 512 KB, so the trivia was pushing the evidence of
        // real freezes out of the file. A quarter second is still well below
        // anything a person would call a stall.
        guard frame > 0, delta > frame * 2, delta >= Self.minimumReportedStall
        else {
            return
        }
        handleStall(deltaSeconds: delta, frameDuration: frame, now: link.timestamp)
    }

    // MARK: - Cold path (stall only)

    private func handleStall(
        deltaSeconds: CFTimeInterval, frameDuration: CFTimeInterval, now: CFTimeInterval
    ) {
        let ms = deltaSeconds * 1_000
        let droppedFrames = frameDuration > 0
            ? max(1, Int((deltaSeconds / frameDuration).rounded()) - 1)
            : 1
        let screen = currentScreenName()
        recordTally(screen: screen, ms: ms)

        if now - windowStart >= 1 {
            if suppressedInWindow > 0 {
                AppLog.perf("… \(suppressedInWindow) more stall(s) suppressed in the last second")
            }
            windowStart = now
            loggedInWindow = 0
            suppressedInWindow = 0
        }
        guard loggedInWindow < maxLogsPerSecond else {
            suppressedInWindow += 1
            return
        }
        loggedInWindow += 1
        let frameWord = droppedFrames == 1 ? "frame" : "frames"
        let line = String(
            format: "stall %.0fms (%d %@ dropped) on %@",
            ms,
            droppedFrames,
            frameWord,
            screen
        )
        // A stall this long is a freeze the user felt, so it is recorded even
        // with verbose logging off. Without it a hang leaves no trace at all,
        // and the silence of this file is what `hang-diag` measures a freeze
        // by — total silence would look exactly like a healthy idle app.
        if ms >= Self.alwaysReportedStallMs {
            AppLog.always("Perf", line)
        } else {
            AppLog.perf(line)
        }
    }

    private func recordTally(screen: String, ms: Double) {
        var tally = tallies[screen] ?? Tally()
        tally.count += 1
        tally.totalMs += ms
        tally.worstMs = max(tally.worstMs, ms)
        tallies[screen] = tally
    }

    private func currentScreenName() -> String {
        guard let root = rootViewControllerProvider?() else {
            return "Unknown"
        }
        return MainThreadWatchdog.resolveScreenName(from: root)
    }

    /// Logs a per-screen tally table: stall count, total stalled time and the
    /// worst single stall, worst screen first.
    func logSummary() {
        guard !tallies.isEmpty else {
            AppLog.perf("session summary: no stalls recorded")
            return
        }
        AppLog.perf("session summary — \(tallies.count) screen(s) with stalls:")
        let ordered = tallies.sorted { $0.value.totalMs > $1.value.totalMs }
        for (screen, tally) in ordered {
            AppLog.perf(
                String(
                    format: "  %@: %d stall(s), %.0fms total, worst %.0fms",
                    screen,
                    tally.count,
                    tally.totalMs,
                    tally.worstMs
                )
            )
        }
    }
}

import Foundation

#if LEGACY_IOS9
extension Timer {
    /// Block-based timers are iOS 10. The target/selector form is iOS 2, so the
    /// block is boxed on an ObjC object that the timer retains and releases with
    /// itself -- no leak, and no change at the call site.
    class func scheduledTimer(
        withTimeInterval interval: TimeInterval,
        repeats: Bool,
        block: @escaping (Timer) -> Void
    ) -> Timer {
        let box = LegacyTimerBox(block)
        return scheduledTimer(
            timeInterval: interval,
            target: box,
            selector: #selector(LegacyTimerBox.fire(_:)),
            userInfo: nil,
            repeats: repeats
        )
    }

    convenience init(
        fire date: Date,
        interval: TimeInterval,
        repeats: Bool,
        block: @escaping (Timer) -> Void
    ) {
        let box = LegacyTimerBox(block)
        self.init(
            fireAt: date,
            interval: interval,
            target: box,
            selector: #selector(LegacyTimerBox.fire(_:)),
            userInfo: nil,
            repeats: repeats
        )
    }
}

/// The timer holds this as its target, so its lifetime matches the timer's.
private final class LegacyTimerBox: NSObject {
    private let block: (Timer) -> Void

    init(_ block: @escaping (Timer) -> Void) {
        self.block = block
    }

    @objc
    func fire(_ timer: Timer) {
        block(timer)
    }
}

extension FileManager {
    /// `temporaryDirectory` is iOS 10; NSTemporaryDirectory() is the same path.
    var temporaryDirectory: URL {
        URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
    }
}
#endif

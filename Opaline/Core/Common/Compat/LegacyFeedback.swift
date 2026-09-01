import UIKit

#if LEGACY_IOS9
// The feedback generators are iOS 10. Shadowed by name so Feedback.swift needs
// no edits.
//
// These are deliberately no-ops rather than approximations: no device that runs
// this build has a Taptic Engine, and Feedback.swift already says so -- the
// visual pop is what actually reaches the user here. Keeping the calls in place
// means the haptic returns for free on any future arm64 target.

final class UIImpactFeedbackGenerator {
    enum FeedbackStyle: Int {
        case light, medium, heavy, soft, rigid
    }

    init(style: FeedbackStyle = .medium) {}
    func prepare() {}
    func impactOccurred() {}
    func impactOccurred(intensity: CGFloat) {}
}

final class UISelectionFeedbackGenerator {
    init() {}
    func prepare() {}
    func selectionChanged() {}
}

final class UINotificationFeedbackGenerator {
    enum FeedbackType: Int {
        case success, warning, error
    }

    init() {}
    func prepare() {}
    func notificationOccurred(_ type: FeedbackType) {}
}
#endif

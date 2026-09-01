import ObjectiveC
import UIKit

#if LEGACY_IOS9
// UIScrollView.refreshControl is iOS 10; adjustedContentInset and
// contentInsetAdjustmentBehavior are iOS 11.

/// Deliberately *not* nested inside UIScrollView and not named
/// ContentInsetAdjustmentBehavior: the SDK already declares that nested name, so
/// a same-named shadow makes lookup inside UIScrollView ambiguous and the
/// property's type unresolvable ("cannot infer contextual base"). Call sites only
/// ever write `.never`, so the spelling of the type never reaches them.
enum LegacyContentInsetAdjustmentBehavior: Int {
    case automatic, scrollableAxes, never, always
}

extension UIScrollView {
    private static var refreshControlKey: UInt8 = 0

    /// Before iOS 10 the documented way to attach a refresh control to a plain
    /// scroll view was to add it as a subview; the control positions itself
    /// against the scroll view's content offset either way.
    var refreshControl: UIRefreshControl? {
        get {
            objc_getAssociatedObject(self, &UIScrollView.refreshControlKey)
                as? UIRefreshControl
        }
        set {
            refreshControl?.removeFromSuperview()
            objc_setAssociatedObject(
                self,
                &UIScrollView.refreshControlKey,
                newValue,
                .OBJC_ASSOCIATION_RETAIN_NONATOMIC
            )
            if let control = newValue {
                // Behind the content, so cells are not drawn over by it.
                insertSubview(control, at: 0)
            }
        }
    }

    /// iOS 11 folded the safe area into the scroll view's own insets. Before
    /// that the controller applied the same adjustment to `contentInset`
    /// directly, so `contentInset` already *is* the adjusted value.
    var adjustedContentInset: UIEdgeInsets {
        contentInset
    }

    private static var adjustmentBehaviorKey: UInt8 = 0

    /// The pre-11 equivalent lives on the view controller, not the scroll view,
    /// so `.never` is forwarded to `automaticallyAdjustsScrollViewInsets`.
    var contentInsetAdjustmentBehavior: LegacyContentInsetAdjustmentBehavior {
        get {
            (objc_getAssociatedObject(self, &UIScrollView.adjustmentBehaviorKey)
                as? NSNumber)
                .flatMap { LegacyContentInsetAdjustmentBehavior(rawValue: $0.intValue) }
                ?? .automatic
        }
        set {
            objc_setAssociatedObject(
                self,
                &UIScrollView.adjustmentBehaviorKey,
                NSNumber(value: newValue.rawValue),
                .OBJC_ASSOCIATION_RETAIN_NONATOMIC
            )
            if let controller = legacyOwningViewController {
                controller.automaticallyAdjustsScrollViewInsets = (newValue != .never)
            }
        }
    }
}
#endif

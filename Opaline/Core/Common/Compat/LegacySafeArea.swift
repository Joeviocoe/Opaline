import ObjectiveC
import UIKit

#if LEGACY_IOS9
// The safe-area API is iOS 11. Supplying it as extensions -- rather than
// renaming 40-odd call sites -- means upstream can keep editing those lines and
// merges stay clean. Swift allows this precisely because at a 9.0 deployment
// target the SDK's own declarations are unavailable, so there is no conflict.
//
// This device has no notch, no home indicator and no rounded corners, so the
// safe area is exactly what iOS 7's topLayoutGuide/bottomLayoutGuide already
// described: the space not covered by the status bar, navigation bar and tab
// bar. That makes these shims exact here, not approximations.

extension UIView {
    /// The view controller managing this view, if it manages one at all.
    ///
    /// `UIViewController` inserts itself into the responder chain between its
    /// root view and that view's superview, so this finds the managing
    /// controller and nothing else.
    var legacyOwningViewController: UIViewController? {
        var responder: UIResponder? = next
        while let current = responder {
            if let controller = current as? UIViewController {
                return controller
            }
            responder = current.next
        }
        return nil
    }
}

extension UIView {
    private static var safeAreaGuideKey: UInt8 = 0

    /// Cached, because callers constrain against it and two different guides
    /// would silently produce two different layouts.
    var safeAreaLayoutGuide: UILayoutGuide {
        if let existing = objc_getAssociatedObject(self, &UIView.safeAreaGuideKey)
            as? UILayoutGuide {
            return existing
        }
        let guide = UILayoutGuide()
        addLayoutGuide(guide)

        var constraints = [
            guide.leadingAnchor.constraint(equalTo: leadingAnchor),
            guide.trailingAnchor.constraint(equalTo: trailingAnchor),
        ]
        // Only a controller's *root* view has bars to avoid; for any other view
        // the safe area is its own bounds, which is what iOS 11 reports too.
        if let controller = legacyOwningViewController, controller.view === self {
            constraints.append(
                guide.topAnchor.constraint(equalTo: controller.topLayoutGuide.bottomAnchor))
            constraints.append(
                guide.bottomAnchor.constraint(equalTo: controller.bottomLayoutGuide.topAnchor))
        } else {
            constraints.append(guide.topAnchor.constraint(equalTo: topAnchor))
            constraints.append(guide.bottomAnchor.constraint(equalTo: bottomAnchor))
        }
        NSLayoutConstraint.activate(constraints)

        objc_setAssociatedObject(
            self, &UIView.safeAreaGuideKey, guide, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        return guide
    }

    var safeAreaInsets: UIEdgeInsets {
        // A window's safe area is the status bar and nothing else here.
        if self is UIWindow {
            let statusBar = UIApplication.shared.statusBarFrame.height
            return UIEdgeInsets(top: statusBar, left: 0, bottom: 0, right: 0)
        }
        guard let controller = legacyOwningViewController, controller.view === self else {
            return .zero
        }
        return UIEdgeInsets(
            top: controller.topLayoutGuide.length,
            left: 0,
            bottom: controller.bottomLayoutGuide.length,
            right: 0
        )
    }
}

extension UIViewController {
    private static var additionalInsetsKey: UInt8 = 0

    /// Stored and readable, but it cannot feed back into the layout the way
    /// iOS 11 does -- there is no safe area for it to extend. Callers that only
    /// set it get the value they expect; layout that must honour it needs an
    /// explicit constraint on this target.
    var additionalSafeAreaInsets: UIEdgeInsets {
        get {
            (objc_getAssociatedObject(self, &UIViewController.additionalInsetsKey)
                as? NSValue)?.uiEdgeInsetsValue ?? .zero
        }
        set {
            objc_setAssociatedObject(
                self,
                &UIViewController.additionalInsetsKey,
                NSValue(uiEdgeInsets: newValue),
                .OBJC_ASSOCIATION_RETAIN_NONATOMIC
            )
        }
    }
}
#endif

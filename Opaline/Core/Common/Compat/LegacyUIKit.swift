import ObjectiveC
import QuartzCore
import UIKit

#if LEGACY_IOS9
// Assorted UIKit members newer than iOS 9, supplied as extensions so no call
// site changes. Grouped by the version that introduced them.

// MARK: - iOS 10

/// The iOS 10 prefetching protocol, shadowed so the two conformances compile.
/// Nothing drives it here -- iOS 9 never calls it -- so prefetching is simply
/// inert until it is driven from `willDisplay:` (a later milestone).
protocol UICollectionViewDataSourcePrefetching: AnyObject {
    func collectionView(
        _ collectionView: UICollectionView,
        prefetchItemsAt indexPaths: [IndexPath]
    )
    func collectionView(
        _ collectionView: UICollectionView,
        cancelPrefetchingForItemsAt indexPaths: [IndexPath]
    )
}

extension UICollectionViewDataSourcePrefetching {
    func collectionView(
        _ collectionView: UICollectionView,
        cancelPrefetchingForItemsAt indexPaths: [IndexPath]
    ) {}
}

extension UICollectionView {
    private static var prefetchKey: UInt8 = 0

    var prefetchDataSource: UICollectionViewDataSourcePrefetching? {
        get {
            objc_getAssociatedObject(self, &UICollectionView.prefetchKey)
                as? UICollectionViewDataSourcePrefetching
        }
        set {
            objc_setAssociatedObject(
                self,
                &UICollectionView.prefetchKey,
                newValue,
                .OBJC_ASSOCIATION_ASSIGN
            )
        }
    }
}

/// Parameter type of the iOS 10 text-view delegate method. Declaring it keeps
/// those signatures compiling; iOS 9 calls the three-argument variant instead,
/// so link taps fall back to UIKit's default handling.
enum UITextItemInteraction: Int {
    case invokeDefaultAction, presentActions, preview
}

extension UIApplication {
    /// iOS 10's completion-handler form. `openURL(_:)` is deprecated but present
    /// since iOS 2 and returns the same success flag synchronously.
    func open(
        _ url: URL,
        options: [String: Any] = [:],
        completionHandler completion: ((Bool) -> Void)? = nil
    ) {
        let opened = openURL(url)
        completion?(opened)
    }
}

// MARK: - iOS 10.3 — alternate icons

extension UIApplication {
    var supportsAlternateIcons: Bool { false }
    var alternateIconName: String? { nil }

    func setAlternateIconName(
        _ alternateIconName: String?,
        completionHandler: ((Error?) -> Void)? = nil
    ) {
        completionHandler?(NSError(
            domain: "LegacyCompat",
            code: -1,
            userInfo: [NSLocalizedDescriptionKey: "Alternate icons require iOS 10.3"]
        ))
    }
}

// MARK: - iOS 11

extension UIStackView {
    /// No per-arranged-view spacing before iOS 11. A transparent spacer of the
    /// difference reproduces it, and only where the gap is actually larger.
    func setCustomSpacing(_ spacing: CGFloat, after arrangedSubview: UIView) {
        guard let index = arrangedSubviews.firstIndex(of: arrangedSubview),
              spacing > self.spacing else {
            return
        }
        let spacer = UIView()
        spacer.isUserInteractionEnabled = false
        spacer.translatesAutoresizingMaskIntoConstraints = false
        let extra = spacing - self.spacing
        if axis == .vertical {
            spacer.heightAnchor.constraint(equalToConstant: extra).isActive = true
        } else {
            spacer.widthAnchor.constraint(equalToConstant: extra).isActive = true
        }
        insertArrangedSubview(spacer, at: index + 1)
    }
}

extension UIScrollView {
    private static var frameGuideKey: UInt8 = 0
    private static var contentGuideKey: UInt8 = 0

    /// Tracks the scroll view's own bounds.
    var frameLayoutGuide: UILayoutGuide {
        legacyGuide(key: &UIScrollView.frameGuideKey) { guide in
            [
                guide.leadingAnchor.constraint(equalTo: self.leadingAnchor),
                guide.trailingAnchor.constraint(equalTo: self.trailingAnchor),
                guide.topAnchor.constraint(equalTo: self.topAnchor),
                guide.bottomAnchor.constraint(equalTo: self.bottomAnchor),
            ]
        }
    }

    /// Tracks the scrollable content. Before iOS 11 a scroll view's subview
    /// constraints *are* its content, so this pins to the same edges -- which is
    /// exactly what the pre-11 idiom did by constraining directly to the scroll
    /// view.
    var contentLayoutGuide: UILayoutGuide {
        legacyGuide(key: &UIScrollView.contentGuideKey) { guide in
            [
                guide.leadingAnchor.constraint(equalTo: self.leadingAnchor),
                guide.trailingAnchor.constraint(equalTo: self.trailingAnchor),
                guide.topAnchor.constraint(equalTo: self.topAnchor),
                guide.bottomAnchor.constraint(equalTo: self.bottomAnchor),
            ]
        }
    }

    private func legacyGuide(
        key: UnsafeRawPointer,
        constraints: (UILayoutGuide) -> [NSLayoutConstraint]
    ) -> UILayoutGuide {
        if let existing = objc_getAssociatedObject(self, key) as? UILayoutGuide {
            return existing
        }
        let guide = UILayoutGuide()
        addLayoutGuide(guide)
        NSLayoutConstraint.activate(constraints(guide))
        objc_setAssociatedObject(self, key, guide, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        return guide
    }
}

extension UIControl.ContentHorizontalAlignment {
    /// iOS 11 added layout-direction-aware alignment. This build is
    /// left-to-right only, so the mapping is exact.
    static var leading: UIControl.ContentHorizontalAlignment { .left }
    static var trailing: UIControl.ContentHorizontalAlignment { .right }
}

extension UIView {
    var effectiveUserInterfaceLayoutDirection: UIUserInterfaceLayoutDirection {
        UIApplication.shared.userInterfaceLayoutDirection
    }
}

extension CALayer {
    /// `maskedCorners` is iOS 11. Rounding every corner is the pre-11 behaviour;
    /// selecting a subset needs a mask layer, which no call site here does often
    /// enough to justify one.
    var maskedCorners: CACornerMask {
        get { CACornerMask(rawValue: 0) }
        set {}
    }
}

struct CACornerMask: OptionSet {
    let rawValue: UInt

    init(rawValue: UInt) { self.rawValue = rawValue }

    static let layerMinXMinYCorner = CACornerMask(rawValue: 1 << 0)
    static let layerMaxXMinYCorner = CACornerMask(rawValue: 1 << 1)
    static let layerMinXMaxYCorner = CACornerMask(rawValue: 1 << 2)
    static let layerMaxXMaxYCorner = CACornerMask(rawValue: 1 << 3)
}

// MARK: - iOS 13 / 15 — present in the source, unreachable on this target
//
// These sit inside `if #available(iOS 15, *)`, so they can never run here, but
// SDK 14.5 does not declare them at all and they still have to compile. Stubs
// that are never reached are cheaper than editing the call sites.

extension UIActivityIndicatorView.Style {
    static var medium: UIActivityIndicatorView.Style { .gray }
    static var large: UIActivityIndicatorView.Style { .whiteLarge }
}

final class UISheetPresentationController {
    struct Detent {
        static func medium() -> Detent { Detent() }
        static func large() -> Detent { Detent() }
    }

    var detents: [Detent] = []
    var prefersGrabberVisible = false
    var selectedDetentIdentifier: String?
}

extension UIViewController {
    /// Always nil, so the `if let` around every use falls through.
    var sheetPresentationController: UISheetPresentationController? { nil }
}

/// iOS 13. Shadowed rather than availability-guarded because the call site
/// constructs one inside `if #available(iOS 15, *)`, and SDK 14.5 does declare
/// the real type -- but only from iOS 13, which this target is below.
final class UITabBarAppearance {
    var backgroundColor: UIColor?
    func configureWithOpaqueBackground() {}
    func configureWithDefaultBackground() {}
}

extension UITabBar {
    var standardAppearance: UITabBarAppearance {
        get { UITabBarAppearance() }
        set {}
    }

    var scrollEdgeAppearance: UITabBarAppearance? {
        get { nil }
        set {}
    }
}

// MARK: - iOS 16 — reachable only behind #available, stubbed to compile

extension UIViewController {
    func setNeedsUpdateOfSupportedInterfaceOrientations() {}

    /// iOS 11. Not an override anywhere, so an extension is enough; the five
    /// places that *override* iOS 11 members carry an @available annotation
    /// instead, since Swift cannot override a member declared in an extension.
    func setNeedsUpdateOfHomeIndicatorAutoHidden() {}
}

/// The call site writes `.iOS(interfaceOrientations:)`, so that factory has to
/// live on the parameter's own type.
struct LegacyGeometryPreferences {
    static func iOS(
        interfaceOrientations: UIInterfaceOrientationMask
    ) -> LegacyGeometryPreferences {
        LegacyGeometryPreferences()
    }
}

// UIWindowScene itself is iOS 13, so the extension carries that availability;
// the call site is already inside `if #available(iOS 16, *)`.
@available(iOS 13.0, *)
extension UIWindowScene {
    func requestGeometryUpdate(
        _ preferences: LegacyGeometryPreferences,
        errorHandler: ((Error) -> Void)? = nil
    ) {}
}
#endif

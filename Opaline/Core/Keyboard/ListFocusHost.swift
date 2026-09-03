import ObjectiveC
import UIKit

/// Everything a screen has to say to get keyboard focus. Conforming is the
/// entire adoption cost — usually a five-line extension in a new file, and for
/// screens whose list is `private`, nothing at all beyond the conformance.
///
/// `listFocusDidReachTop()` is a *requirement*, not merely an extension
/// method with a default — that distinction is load-bearing. A method that
/// exists only in a protocol extension is dispatched statically against the
/// declared type of the reference, not the runtime type: calling it through
/// `focusHost: ListFocusHost?` would always hit the extension's default body,
/// never a conforming screen's own override, no matter what that override
/// says. Confirmed on device: `SearchViewController`'s override never ran
/// once, in any session, despite compiling and linking correctly every time.
/// Putting the signature in the protocol body switches it to witness-table
/// (dynamic) dispatch, which is the only way an override is ever reachable
/// through a protocol-typed reference.
protocol ListFocusHost: UIViewController {
    var listFocusScrollView: UIScrollView? { get }
    var listFocusAxis: ListFocusController.Axis { get }
    func listFocusDidReachTop() -> Bool
}

extension ListFocusHost {
    /// Finds the screen's list by looking for one. Several screens keep their
    /// table in a `private let`, which a conformance in another file cannot
    /// reach; `LibraryViewController.scrollToTop()` already resorts to the same
    /// search, so this is the house answer rather than a new trick.
    var listFocusScrollView: UIScrollView? {
        ListFocusFinder.firstList(in: view)
    }

    var listFocusAxis: ListFocusController.Axis { .list }

    /// Called when Up is pressed on the topmost item. Return true to claim it
    /// — Search overrides this to hand the chain back to its text field, so
    /// the arrow keys move between the field and the list rather than
    /// dead-ending. Most screens have nowhere else for focus to go, hence the
    /// default rather than making every conformer write `{ false }` itself.
    func listFocusDidReachTop() -> Bool { false }

    /// The video behind a focused cell, derived the same way Return already
    /// opens one: by asking the cell that is actually on screen at that index
    /// path, not a per-screen accessor a new list has to remember to write.
    /// `didSelectItemAt`/`didSelectRowAt` already work on every screen with
    /// zero wiring for exactly this reason — every video-bearing cell class
    /// in the app (`VideoCell`, `SubscriptionVideoCell`, `ShortThumbnailCell`)
    /// conforms to `FocusableVideoCell` once, and every screen that reuses one
    /// of them gets `q` for free, forever, including screens that do not
    /// exist yet. The one gap is `ShelfRailCell`, which is a whole rail of
    /// videos behind a single index path — there is no single video to name
    /// without knowing which item inside the rail has focus, which nothing
    /// tracks today.
    func listFocusVideo(at indexPath: IndexPath) -> Video? {
        (listFocusScrollView as? FocusGeometry)?
            .focusCell(at: indexPath)
            .flatMap { ($0 as? FocusableVideoCell)?.focusVideo }
    }
}

/// Marker for a cell that knows which video it is currently showing. Conform
/// once per cell class; see `ListFocusHost.listFocusVideo(at:)`.
protocol FocusableVideoCell: AnyObject {
    var focusVideo: Video? { get }
}

/// For screens that want key commands but have no list to focus.
///
/// The responder chain runs *upward* from the first responder, so a controller
/// that never becomes one is simply never asked for its `keyCommands` — no
/// matter that it is on screen. Screens with a list get this for free, because
/// their ring takes the chain when it enters the window. Shorts has no ring
/// (one item per page: "focused" and "on screen" are the same thing), so it
/// says so here instead.
protocol KeyboardCommandResponder: UIViewController {}

enum ListFocusFinder {
    /// Breadth-first, so a list that is a direct child wins over one buried in
    /// a header or an embedded child controller.
    static func firstList(in root: UIView) -> UIScrollView? {
        var queue: [UIView] = root.subviews
        var index = 0
        while index < queue.count {
            let candidate = queue[index]
            index += 1
            if candidate is UICollectionView || candidate is UITableView {
                return candidate as? UIScrollView
            }
            queue.append(contentsOf: candidate.subviews)
        }
        return nil
    }
}

/// Attaches a `ListFocusController` to a screen, once.
///
/// Driven from `RotatingNavigationController`'s existing `didShow` delegate
/// callback, which is the one place every screen in the app passes through —
/// the four tabs, the Library's three embedded navigation controllers, pushed
/// Search / Channel / Shorts, and the watch screen inside the player panel's
/// navigation wrapper.
/// File scope on purpose. `&ListFocusInstaller.someStaticVar` is the usual
/// idiom, but Swift only guarantees a stable address for a genuine global, and
/// an unstable key makes every lookup miss — which reads exactly like the guard
/// below never running.
private var listFocusControllerKey: UInt8 = 0

enum ListFocusInstaller {
    /// A ringless screen has to take the chain itself, or it is never asked
    /// for its commands.
    private static func claimChain(for viewController: UIViewController) {
        guard let responder = viewController as? KeyboardCommandResponder else {
            return
        }
        guard !responder.isFirstResponder else {
            return
        }
        KeyboardFocusCoordinator.shared.ringlessDidAppear(responder)
        let accepted = responder.becomeFirstResponder()
        KeyboardDiagnostics.logResponder(
            "ringless becomeFirstResponder",
            responder,
            accepted: accepted
        )
    }

    /// Belt and braces beside the associated-object guard. `didShow` fires
    /// more than once per appearance -- RotatingNavigationController calls
    /// realignChevron from four places for the same reason -- and a second
    /// ring on one scroll view means a second KVO observer and every keypress
    /// handled twice, which on device showed up as focus moves 6ms apart.
    private static func hasRing(
        _ scrollView: UIScrollView,
        host: ListFocusHost,
        hostID: UInt
    ) -> Bool {
        guard scrollView.subviews.contains(where: { $0 is ListFocusRingView }) else {
            return false
        }
        KeyboardDiagnostics.log(
            "focus install skipped: ring already on \(type(of: host)) #\(hostID)"
        )
        return true
    }

    static func install(in viewController: UIViewController) {
        claimChain(for: viewController)
        guard let host = viewController as? ListFocusHost else {
            return
        }
        let hostID = UInt(bitPattern: ObjectIdentifier(host))
        guard objc_getAssociatedObject(host, &listFocusControllerKey) == nil else {
            return
        }
        guard let scrollView = host.listFocusScrollView,
              let geometry = scrollView as? FocusGeometry
        else {
            KeyboardDiagnostics.log("focus install skipped: no list on \(type(of: host))")
            return
        }
        guard !hasRing(scrollView, host: host, hostID: hostID) else {
            return
        }
        attach(to: host, geometry: geometry, hostID: hostID)
    }

    /// The controller is held by an associated object rather than a stored
    /// property, so no screen has to declare one to adopt focus.
    private static func attach(
        to host: ListFocusHost,
        geometry: FocusGeometry,
        hostID: UInt
    ) {
        let controller = ListFocusController(
            axis: host.listFocusAxis,
            geometry: geometry,
            host: host
        )
        objc_setAssociatedObject(
            host,
            &listFocusControllerKey,
            controller,
            .OBJC_ASSOCIATION_RETAIN_NONATOMIC
        )
        // The host id tells a re-install apart from a recreated controller.
        KeyboardDiagnostics.log(
            "focus installed on \(type(of: host)) #\(hostID) axis=\(host.listFocusAxis)"
        )
    }
}

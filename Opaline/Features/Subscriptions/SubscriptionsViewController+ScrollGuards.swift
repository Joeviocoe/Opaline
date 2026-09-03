import UIKit

// MARK: - Scroll guards
//
// Invariants for the subscriptions table's scroll geometry, kept separate
// from the local-library source because they are not about it: the same
// table, and the same navigation-bar auto-hiding, exist on the account path.

extension SubscriptionsViewController {
    /// A negative top inset is never something this screen asks for, so undo
    /// it wherever it came from.
    ///
    /// Captured on the device: `insetTop=-6000` with `offset=6000`, tracking
    /// `-offset` almost exactly, while the header and content were both
    /// healthy (`headerH=88`, `content=6688`, `rows=30`). A top inset of
    /// -6000 tells the scroll view its top *is* offset 6000, so the list
    /// still scrolls down but cannot come back up, and the channel bar above
    /// that line is unreachable. That is the "stuck below the header" report.
    ///
    /// No code in this app writes it. UIKit does: this screen is the one
    /// scrolling surface that never sets `contentInsetAdjustmentBehavior`
    /// to `.never` — the player, queue and Shorts screens all do — so
    /// `automaticallyAdjustsScrollViewInsets` stays on and UIKit owns the
    /// inset, while `TopBarAutoHider` toggles the navigation bar underneath
    /// it and makes UIKit recompute constantly.
    ///
    /// Opting out instead would hand this screen an inset it does not
    /// currently manage — the table is pinned to `view.topAnchor` and relies
    /// on that adjustment to clear the bar. So this asserts the invariant
    /// rather than claiming to know UIKit's trigger, and logs when it fires
    /// so the trigger can be found from evidence rather than argued about.
    func clampNegativeTopInset() {
        guard tableView.contentInset.top < 0 else {
            return
        }
        let was = Int(tableView.contentInset.top)
        let offset = Int(tableView.contentOffset.y)
        tableView.contentInset.top = 0
        AppLog.subs(
            "inset guard: top \(was) -> 0 (offset=\(offset)"
                + " content=\(Int(tableView.contentSize.height))"
                + " barHidden=\(topBarHider.isHidden))"
        )
    }
}

import UIKit

/// Shorts get no focus ring: the feed is one item per page, so "focused" and
/// "on screen" are the same thing. Up and down page it instead, reusing the
/// existing scroll-driven settle — `scrollViewDidEndScrollingAnimation` already
/// calls `settleOnCurrentPage()`, which attaches the player.
extension ShortsViewController: KeyboardCommandResponder {
    override var canBecomeFirstResponder: Bool { true }

    override var keyCommands: [UIKeyCommand]? {
        guard !KeyboardInputMonitor.shared.isEditingText else {
            return nil
        }
        return KeyCommandCatalog.shorts
    }

    @objc
    func keyboardNextShort() {
        page(by: 1)
    }

    @objc
    func keyboardPreviousShort() {
        page(by: -1)
    }

    @objc
    func keyboardTogglePlayback() {
        KeyboardDiagnostics.logTimed("shorts toggle playback")
        playerView.setPaused(!playerView.isPaused)
    }

    private func page(by delta: Int) {
        let height = collectionView.bounds.height
        guard height > 0 else {
            return
        }
        let current = Int((collectionView.contentOffset.y / height).rounded())
        let target = current + delta
        guard target >= 0,
              target < collectionView.numberOfItems(inSection: 0)
        else {
            KeyboardDiagnostics.logTimed("shorts page \(delta) out of range")
            return
        }
        KeyboardDiagnostics.logTimed("shorts page \(current)->\(target)")
        collectionView.setContentOffset(
            CGPoint(x: 0, y: CGFloat(target) * height),
            animated: true
        )
    }
}

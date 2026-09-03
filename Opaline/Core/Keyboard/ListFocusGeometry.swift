import UIKit

/// Which way focus is being asked to move.
enum FocusDirection {
    case up, down, left, right
}

/// The list, reduced to the four things focus needs from it, all in *content*
/// coordinates — which is the space the ring lives in, so nothing has to be
/// converted on the way through.
///
/// Both conformances below use APIs from iOS 2/6. There is no focus engine to
/// lean on here: `UIFocusSystem` is iOS 15, and `UIFocusEnvironment`, though it
/// exists from iOS 9, only ever did anything on tvOS.
protocol FocusGeometry: AnyObject {
    var focusScrollView: UIScrollView { get }
    var focusSectionCount: Int { get }
    func focusItemCount(inSection section: Int) -> Int
    func focusFrame(for indexPath: IndexPath) -> CGRect?
    func focusCandidates(in rect: CGRect) -> [IndexPath]
    func focusSelect(_ indexPath: IndexPath)
}

extension FocusGeometry {
    /// The first item that exists, scanning forward from the top. Sections can
    /// legitimately be empty — the subscriptions feed builds a shorts shelf as
    /// its own section and drops it when there is nothing to show.
    func firstFocusableIndexPath() -> IndexPath? {
        for section in 0..<focusSectionCount where focusItemCount(inSection: section) > 0 {
            return IndexPath(item: 0, section: section)
        }
        return nil
    }

    func isValid(_ indexPath: IndexPath) -> Bool {
        guard indexPath.section >= 0, indexPath.section < focusSectionCount else {
            return false
        }
        return indexPath.item >= 0
            && indexPath.item < focusItemCount(inSection: indexPath.section)
    }
}

// MARK: - UITableView

extension UITableView: FocusGeometry {
    var focusScrollView: UIScrollView { self }
    var focusSectionCount: Int { numberOfSections }

    func focusItemCount(inSection section: Int) -> Int {
        numberOfRows(inSection: section)
    }

    func focusFrame(for indexPath: IndexPath) -> CGRect? {
        guard isValid(indexPath) else {
            return nil
        }
        return rectForRow(at: indexPath)
    }

    func focusCandidates(in rect: CGRect) -> [IndexPath] {
        indexPathsForRows(in: rect) ?? []
    }

    func focusSelect(_ indexPath: IndexPath) {
        let target = delegate?.tableView?(self, willSelectRowAt: indexPath)
            ?? indexPath
        delegate?.tableView?(self, didSelectRowAt: target)
    }
}

// MARK: - UICollectionView

extension UICollectionView: FocusGeometry {
    var focusScrollView: UIScrollView { self }
    var focusSectionCount: Int { numberOfSections }

    func focusItemCount(inSection section: Int) -> Int {
        numberOfItems(inSection: section)
    }

    func focusFrame(for indexPath: IndexPath) -> CGRect? {
        guard isValid(indexPath) else {
            return nil
        }
        return collectionViewLayout
            .layoutAttributesForItem(at: indexPath)?
            .frame
    }

    /// Cells only. Section headers carry index paths too, and focusing one
    /// would land the ring on a shelf title with nothing to open.
    func focusCandidates(in rect: CGRect) -> [IndexPath] {
        let attributes = collectionViewLayout
            .layoutAttributesForElements(in: rect) ?? []
        return attributes
            .filter { $0.representedElementCategory == .cell }
            .map { $0.indexPath }
    }

    func focusSelect(_ indexPath: IndexPath) {
        let allowed = delegate?.collectionView?(
            self,
            shouldSelectItemAt: indexPath
        ) ?? true
        guard allowed else {
            return
        }
        delegate?.collectionView?(self, didSelectItemAt: indexPath)
    }
}

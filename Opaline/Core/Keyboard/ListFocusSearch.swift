import UIKit

/// Directional movement across a list, done geometrically.
///
/// The obvious implementation — index ± column count — is wrong here, and not
/// in a corner case. `VideosViewController` renders three different cell
/// shapes in one collection view: grid `VideoCell`s, taller `ShortThumbnailCell`s
/// when the shorts grid is on, and full-width `ShelfRailCell` rows when the
/// feed is railed. Column arithmetic is right for the first and wrong for the
/// other two, and wrong again across a section boundary where the shape
/// changes mid-feed.
///
/// Comparing frames costs a layout query on a keypress and is right for all
/// three without knowing which is on screen.
enum ListFocusSearch {
    /// How far beyond the viewport to consider candidates. Two screens is
    /// enough to cross a tall rail cell without walking the whole feed, which
    /// on a long Home page would be thousands of attributes.
    private static let searchMargin: CGFloat = 2

    static func next(
        from current: IndexPath,
        direction: FocusDirection,
        geometry: FocusGeometry
    ) -> IndexPath? {
        guard let origin = geometry.focusFrame(for: current) else {
            return nil
        }
        let scored = geometry.focusCandidates(in: searchRect(around: origin, geometry: geometry))
            .filter { $0 != current }
            .compactMap { path -> (IndexPath, CGFloat, CGFloat)? in
                guard let frame = geometry.focusFrame(for: path),
                      let score = self.score(
                          from: origin,
                          to: frame,
                          direction: direction
                      )
                else {
                    return nil
                }
                return (path, score.0, score.1)
            }
        let best = scored.min { lhs, rhs in
            lhs.1 == rhs.1 ? lhs.2 < rhs.2 : lhs.1 < rhs.1
        }
        return best?.0
    }

    /// The slice of layout worth comparing against. Two viewports is enough to
    /// step across a full-width rail cell without walking a feed that may hold
    /// thousands of items.
    ///
    /// Width is `origin.maxX` plus a full viewport, not `max(bounds.width,
    /// origin.maxX)` -- the old formula capped the rect's right edge at the
    /// focused item's *own* edge the moment origin.maxX overtook bounds.width,
    /// so nothing further right could ever be found. Invisible on `.list` /
    /// `.grid`, where an item's content-space maxX never exceeds the
    /// viewport width. Not on `.row`: the channel bar scrolls its own items
    /// horizontally past that width after only a few avatars, and every one
    /// beyond the first screenful was silently unreachable by `→` -- not a
    /// reveal/scroll problem, movement itself never found them.
    private static func searchRect(
        around origin: CGRect,
        geometry: FocusGeometry
    ) -> CGRect {
        let bounds = geometry.focusScrollView.bounds
        let margin = bounds.height * searchMargin
        return CGRect(
            x: 0,
            y: origin.midY - margin,
            width: origin.maxX + bounds.width,
            height: margin * 2
        )
    }

    /// `(primary, cross)` distance, or nil when the candidate does not lie in
    /// the requested direction at all. Primary is compared first so the
    /// nearest row wins outright, and cross only breaks ties within it.
    private static func score(
        from origin: CGRect,
        to candidate: CGRect,
        direction: FocusDirection
    ) -> (CGFloat, CGFloat)? {
        let dx = candidate.midX - origin.midX
        let dy = candidate.midY - origin.midY
        switch direction {
        case .up:
            guard candidate.midY < origin.minY else {
                return nil
            }
            return (abs(dy), abs(dx))
        case .down:
            guard candidate.midY > origin.maxY else {
                return nil
            }
            return (abs(dy), abs(dx))
        case .left:
            guard dx < 0, abs(dy) < origin.height else {
                return nil
            }
            return (abs(dx), abs(dy))
        case .right:
            guard dx > 0, abs(dy) < origin.height else {
                return nil
            }
            return (abs(dx), abs(dy))
        }
    }

    /// Flattened ±1 across section boundaries — what a single-column list
    /// wants, and the fallback when the geometric search comes up empty at a
    /// ragged row end.
    static func step(
        from current: IndexPath,
        forward: Bool,
        geometry: FocusGeometry
    ) -> IndexPath? {
        if forward {
            let nextItem = IndexPath(
                item: current.item + 1,
                section: current.section
            )
            if geometry.isValid(nextItem) {
                return nextItem
            }
            return firstItem(ofSectionAfter: current.section, geometry: geometry)
        }
        if current.item > 0 {
            return IndexPath(item: current.item - 1, section: current.section)
        }
        return lastItem(ofSectionBefore: current.section, geometry: geometry)
    }

    static func firstItem(
        ofSectionAfter section: Int,
        geometry: FocusGeometry
    ) -> IndexPath? {
        var next = section + 1
        while next < geometry.focusSectionCount {
            if geometry.focusItemCount(inSection: next) > 0 {
                return IndexPath(item: 0, section: next)
            }
            next += 1
        }
        return nil
    }

    static func lastItem(
        ofSectionBefore section: Int,
        geometry: FocusGeometry
    ) -> IndexPath? {
        var previous = section - 1
        while previous >= 0 {
            let count = geometry.focusItemCount(inSection: previous)
            if count > 0 {
                return IndexPath(item: count - 1, section: previous)
            }
            previous -= 1
        }
        return nil
    }
}

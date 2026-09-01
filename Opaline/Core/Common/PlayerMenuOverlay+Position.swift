import UIKit

// MARK: - Anchored placement

/// Positions the panel next to a tapped control instead of centering it.
/// Split out of `PlayerMenuOverlay.swift` to keep that file under the
/// length limit; the math only needs `Metrics`, so it stays internal.
extension PlayerMenuOverlay {
    /// Mirrors the constraint math in `titleAndScrollConstraints` closely
    /// enough to pick a placement that already fits; the real height caps
    /// still apply, this only decides where to anchor.
    static func estimatedHeight(hasTitle: Bool, itemCount: Int) -> CGFloat {
        let rowsHeight = min(CGFloat(itemCount) * Metrics.rowHeight, Metrics.maxRowsHeight)
        guard hasTitle else {
            return 8 + rowsHeight + 8
        }
        let titleFont = UIFont.systemFont(ofSize: Metrics.titleFontSize, weight: .semibold)
        return 14 + titleFont.lineHeight + 8 + rowsHeight + 8
    }

    /// Prefers below the rect, right-aligned to its trailing edge; flips
    /// above on bottom overflow; always clamped inside `hostBounds` with
    /// an `edgeMargin` gutter.
    static func panelOrigin(
        hostBounds: CGRect,
        sourceRect: CGRect,
        estimatedHeight: CGFloat
    ) -> CGPoint {
        let margin = Metrics.edgeMargin
        let width = Metrics.panelWidth
        let maxX = hostBounds.width - margin - width
        let x = min(max(sourceRect.maxX - width, margin), max(margin, maxX))
        var y = sourceRect.maxY + margin
        if y + estimatedHeight > hostBounds.height - margin {
            y = sourceRect.minY - margin - estimatedHeight
        }
        let maxY = hostBounds.height - margin - estimatedHeight
        y = min(max(y, margin), max(margin, maxY))
        return CGPoint(x: x, y: y)
    }

    /// Centers the panel when there is no anchor (the player menus, which
    /// must not change). Otherwise pins it via a precomputed origin so it
    /// never fights the height caps in `activatePanelConstraints` with a
    /// conflicting constraint.
    func positionConstraints(
        sourceRect: CGRect?,
        hasTitle: Bool
    ) -> [NSLayoutConstraint] {
        guard let sourceRect = sourceRect else {
            return [
                panel.centerXAnchor.constraint(equalTo: centerXAnchor),
                panel.centerYAnchor.constraint(equalTo: centerYAnchor)
            ]
        }
        let height = PlayerMenuOverlay.estimatedHeight(
            hasTitle: hasTitle, itemCount: items.count
        )
        let origin = PlayerMenuOverlay.panelOrigin(
            hostBounds: bounds,
            sourceRect: sourceRect,
            estimatedHeight: height
        )
        return [
            panel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: origin.x),
            panel.topAnchor.constraint(equalTo: topAnchor, constant: origin.y)
        ]
    }
}

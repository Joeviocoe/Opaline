import Foundation

/// A chip on the home screen.
struct HomeCategory: Equatable {
    enum Kind: Equatable {
        /// The personalized home feed ("All").
        case feed
        /// Filters the feed by a shelf title collected at runtime.
        case shelf
        /// Pulsing stand-in while shelf chips are being collected.
        case placeholder
        /// One-shot TV destination page (no pagination — the server
        /// returns the whole page at once).
        case destination(browseId: String)
    }

    static let feed = HomeCategory(
        label: "home.category.all".localized, kind: .feed
    )
    static let placeholder = HomeCategory(label: "", kind: .placeholder)

    /// Static tail — TV destination pages, kept after the dynamic
    /// shelf chips.
    static let destinations: [HomeCategory] = [
        HomeCategory(
            label: "home.category.live".localized,
            kind: .destination(browseId: BrowseID.liveDestination)
        ),
        HomeCategory(
            label: "home.category.news".localized,
            kind: .destination(browseId: BrowseID.newsDestination)
        ),
        HomeCategory(
            label: "home.category.gaming".localized,
            kind: .destination(browseId: BrowseID.gamingDestination)
        ),
        HomeCategory(
            label: "home.category.sports".localized,
            kind: .destination(browseId: BrowseID.sportsDestination)
        ),
        HomeCategory(
            label: "home.category.learning".localized,
            kind: .destination(browseId: BrowseID.learningDestination)
        ),
        HomeCategory(
            label: "home.category.fashion".localized,
            kind: .destination(browseId: BrowseID.fashionDestination)
        )
    ]

    let label: String
    let kind: Kind
}

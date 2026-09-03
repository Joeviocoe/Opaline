import UIKit

/// The Library's three embedded screens. Each keeps its table in a `private`
/// property, so these rely on `ListFocusHost`'s default search of the view
/// hierarchy — the same approach `LibraryViewController.scrollToTop()` already
/// takes for the same reason. The conformance is the entire cost.
extension HistoryViewController: ListFocusHost {}

extension DownloadsViewController: ListFocusHost {}

extension PlaylistsViewController: ListFocusHost {}

extension PlaylistVideosViewController: ListFocusHost {}

extension SubscribedChannelsViewController: ListFocusHost {}

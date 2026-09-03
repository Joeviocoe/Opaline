import UIKit

/// The Library's three embedded screens, plus the "All" channel list. Each
/// keeps its list in a `private` property, so these rely on `ListFocusHost`'s
/// default search of the view hierarchy — the same approach
/// `LibraryViewController.scrollToTop()` already takes for the same reason.
///
/// No `listFocusVideo(at:)` overrides — History, Downloads and Playlist
/// videos all dequeue `SubscriptionVideoCell`, which conforms to
/// `FocusableVideoCell`, so `ListFocusHost`'s generic default already answers
/// `q` correctly by asking whichever cell is on screen. Playlists and
/// Subscribed Channels show playlists/channels, not videos — `q` correctly
/// finds nothing there, which is what the generic default already returns
/// for a cell that isn't one of the video-bearing classes.
extension HistoryViewController: ListFocusHost {}

extension DownloadsViewController: ListFocusHost {}

extension PlaylistsViewController: ListFocusHost {}

extension PlaylistVideosViewController: ListFocusHost {}

extension SubscribedChannelsViewController: ListFocusHost {}

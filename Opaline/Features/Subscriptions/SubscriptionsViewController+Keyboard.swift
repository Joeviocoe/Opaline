import UIKit

/// A single-column list, so it deliberately does not claim the horizontal
/// arrows — they fall through the chain to the player, which is what lets a
/// video keep its seek keys while the subscriptions feed is on screen.
///
/// No `listFocusVideo(at:)` override — rows are a mix of `.video` (a
/// `SubscriptionVideoCell`, which conforms to `FocusableVideoCell`) and the
/// shorts shelf (`ShortsShelfCell`, which does not). `ListFocusHost`'s
/// generic default asks whichever cell is actually on screen, so it already
/// answers a video for one and nil for the other with no help from this file.
extension SubscriptionsViewController: ListFocusHost {}

import Foundation

/// One page of search results plus the token for the next page (nil = last).
struct SearchPage {
    let videos: [Video]
    let continuation: String?
}

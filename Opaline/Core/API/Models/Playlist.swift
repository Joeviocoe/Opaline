import Foundation

struct Playlist {
    let id: String
    let title: String
    let description: String
    let thumbnailURL: String?
    let itemCount: Int?
}

/// One row of the "save to playlist" sheet, as served by
/// `/playlist/get_add_to_playlist` for a specific video. Read-only playlists
/// (Liked videos) are absent, and titles arrive already localized.
struct PlaylistAddOption {
    let id: String
    let title: String
    /// Whether the video is already in this playlist — server truth, so it
    /// also covers additions made on other devices.
    let isAdded: Bool
    /// Edit actions handed to us by YouTube; sent back verbatim rather than
    /// rebuilt, so removal doesn't need a separate `setVideoId` lookup.
    let addActions: [[String: Any]]
    let removeActions: [[String: Any]]
}

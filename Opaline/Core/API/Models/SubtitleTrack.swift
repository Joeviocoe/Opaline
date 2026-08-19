import Foundation

struct SubtitleTrack: Codable {
    let name: String
    let languageCode: String
    let url: URL
    var isAsr: Bool = false
}

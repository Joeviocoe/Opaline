import Foundation

enum LikeStatus: String, Codable {
    case like = "LIKE"
    case dislike = "DISLIKE"
    case indifferent = "INDIFFERENT"
}

struct Video: Codable {
    let id: String
    let title: String
    // Channel fields are vars so copies can be enriched in place
    // (e.g. channel-tab videos missing owner metadata).
    var channelId: String?
    var channelName: String
    var channelAvatarURL: String?
    let thumbnailURL: String
    let viewCount: String?
    let publishedAt: String?
    let duration: String?
    let isLive: Bool
    let playlistId: String?
    /// YouTube Short — opens in the vertical swipe viewer, not the watch
    /// screen. A var so the feed parser can flag renderers that carry a
    /// short behind ordinary video chrome.
    var isShort: Bool

    init(
        id: String,
        title: String,
        channelId: String?,
        channelName: String,
        channelAvatarURL: String?,
        thumbnailURL: String,
        viewCount: String?,
        publishedAt: String?,
        duration: String?,
        isLive: Bool = false,
        playlistId: String? = nil,
        isShort: Bool = false
    ) {
        self.id = id
        self.title = title
        self.channelId = channelId
        self.channelName = channelName
        self.channelAvatarURL = channelAvatarURL
        self.thumbnailURL = thumbnailURL
        self.viewCount = viewCount
        self.publishedAt = publishedAt
        self.duration = duration
        self.isLive = isLive
        self.playlistId = playlistId
        self.isShort = isShort
    }

    /// Minimal stub for a video known only by id — e.g. a deep link.
    /// `WatchViewController` refetches everything from the network by
    /// videoId, so the placeholder fields are only ever shown for the
    /// instant before that fetch replaces them.
    init(id: String, isShort: Bool = false, playlistId: String? = nil) {
        self.id = id
        self.isShort = isShort
        self.playlistId = playlistId
        title = ""
        channelId = nil
        channelName = ""
        channelAvatarURL = nil
        thumbnailURL = ""
        viewCount = nil
        publishedAt = nil
        duration = nil
        isLive = false
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        title = try container.decode(String.self, forKey: .title)
        channelId = try container.decodeIfPresent(String.self, forKey: .channelId)
        channelName = try container.decode(String.self, forKey: .channelName)
        channelAvatarURL = try container.decodeIfPresent(
            String.self, forKey: .channelAvatarURL
        )
        thumbnailURL = try container.decode(String.self, forKey: .thumbnailURL)
        viewCount = try container.decodeIfPresent(String.self, forKey: .viewCount)
        publishedAt = try container.decodeIfPresent(
            String.self, forKey: .publishedAt
        )
        duration = try container.decodeIfPresent(String.self, forKey: .duration)
        isLive = try container.decodeIfPresent(Bool.self, forKey: .isLive) ?? false
        playlistId = try container.decodeIfPresent(String.self, forKey: .playlistId)
        isShort = try container.decodeIfPresent(Bool.self, forKey: .isShort) ?? false
    }
}

struct ChannelInfo: Codable {
    let id: String
    let title: String
    let avatarURL: String?
    let subscriberCountText: String?
    let bannerURL: String?
    let isVerified: Bool
    let description: String?
    let contactInfo: String?
    let videoCountText: String?
}

struct ChannelPage {
    var info: ChannelInfo
    let videosPage: FeedPage
    let subscribeButtonText: String?
    let isSubscribed: Bool
}

struct WatchPage {
    let video: Video
    let description: String?
    let channelInfo: ChannelInfo?
    let subscribeButtonText: String?
    let isSubscribed: Bool
    let relatedVideos: [Video]
    let likeCount: String?
    let likeStatus: LikeStatus?
    /// Total comments as the server formats it ("13K") — the Shorts rail
    /// shows it without paying for a comments fetch.
    let commentCount: String?
    let nextVideo: Video?
    let playlistTitle: String?
    let playlistVideos: [Video]?
}

struct Comment {
    let id: String
    let authorName: String
    let authorChannelId: String?
    let authorAvatarURL: String?
    let content: String
    let publishedTime: String?
    let likeCount: String?
    let replyCount: String?
    let isPinned: Bool
    /// Token that loads this thread's replies, `nil` when it has none.
    /// Replies are one level deep on YouTube — a reply never carries one.
    let replyContinuation: String?
}

struct CommentsPage {
    let title: String?
    let comments: [Comment]
    let continuation: String?
    /// "Top" / "Newest", straight from the header's sort menu — the server
    /// sends both the localized title and a ready continuation token, so
    /// nothing has to be built or translated here. Only the first page of a
    /// sort order carries them.
    let sortOptions: [CommentSortOption]
}

struct CommentSortOption {
    let title: String
    let token: String
    let isSelected: Bool
}

final class ChannelInfoStore {
    static let shared = ChannelInfoStore()

    /// A feed page carries a hundred-odd distinct channels and each one
    /// costs a browse request. Sent all at once they fill the six
    /// connections iOS opens per host, and everything else queued behind
    /// them — the next feed page waited ten seconds for avatars.
    ///
    /// ponytail: fixed cap; the number only matters relative to the
    /// six-connection limit, so it needs no tuning knob.
    private static let maxConcurrentFetches = 3

    private var channelService: ChannelService?
    private let queue = DispatchQueue(label: "com.ytvlite.channel-info-store")
    private var cache: [String: ChannelInfo] = [:]
    private var pending: [String: [(Result<ChannelInfo, Error>) -> Void]] = [:]
    /// Both only touched on `queue`.
    private var activeFetches = 0
    private var waiting: [String] = []

    private init() {}

    func configure(channelService: ChannelService) {
        self.channelService = channelService
    }

    func fetch(
        channelId: String,
        completion: @escaping (Result<ChannelInfo, Error>) -> Void
    ) {
        // ALL cache/pending accesses must go through queue to
        // avoid data races on the dictionary.
        queue.async {
            if let cached = self.cache[channelId] {
                DispatchQueue.main.async {
                    completion(.success(cached))
                }
                return
            }

            if self.pending[channelId] != nil {
                self.pending[channelId]?.append(completion)
                return
            }

            if let cached = self.loadFromDisk(channelId: channelId) {
                DispatchQueue.main.async {
                    completion(.success(cached))
                }
                return
            }

            self.fetchFromNetwork(
                channelId: channelId,
                completion: completion
            )
        }
    }

    private func loadFromDisk(channelId: String) -> ChannelInfo? {
        guard let cached = AppCache.shared.cachedChannelInfo(channelId: channelId)
        else { return nil }
        cache[channelId] = cached
        return cached
    }

    private func fetchFromNetwork(
        channelId: String,
        completion: @escaping (Result<ChannelInfo, Error>) -> Void
    ) {
        guard let channelService else {
            assertionFailure("ChannelInfoStore is not configured")
            DispatchQueue.main.async {
                completion(.failure(APIError.invalidResponse))
            }
            return
        }
        pending[channelId] = [completion]
        guard activeFetches < Self.maxConcurrentFetches else {
            waiting.append(channelId)
            return
        }
        startFetch(channelId: channelId, service: channelService)
    }

    /// Call on `queue`.
    private func startFetch(channelId: String, service: ChannelService) {
        activeFetches += 1
        AppLog.channel("info fetch \(channelId)")
        service.fetchChannelInfo(channelId: channelId) { result in
            self.queue.async {
                self.activeFetches -= 1
                self.storeResult(result, channelId: channelId)
                let callbacks = self.pending.removeValue(forKey: channelId) ?? []
                DispatchQueue.main.async { callbacks.forEach { $0(result) } }
                self.startNextWaiting()
            }
        }
    }

    /// Call on `queue`.
    private func storeResult(
        _ result: Result<ChannelInfo, Error>,
        channelId: String
    ) {
        switch result {
        case .success(let info):
            cache[channelId] = info
            AppCache.shared.setChannelInfo(info, channelId: channelId)
        case .failure(let error):
            AppLog.channel("info fetch failed \(channelId): \(error)")
        }
    }

    /// Call on `queue`.
    private func startNextWaiting() {
        guard activeFetches < Self.maxConcurrentFetches,
              let service = channelService,
              !waiting.isEmpty
        else {
            return
        }
        startFetch(channelId: waiting.removeFirst(), service: service)
    }
}

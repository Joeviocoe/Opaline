import Foundation

/// User-selectable search filters, encoded into the Innertube /search
/// `params` field (the same protobuf schema Invidious and yt-dlp use).
struct SearchFilters: Equatable {
    enum Sort: Int, CaseIterable {
        case relevance = 0
        case rating = 1
        case uploadDate = 2
        case viewCount = 3

        var displayName: String {
            switch self {
            case .relevance:
                return "search.sort.relevance".localized
            case .rating:
                return "search.sort.rating".localized
            case .uploadDate:
                return "search.sort.uploadDate".localized
            case .viewCount:
                return "search.sort.viewCount".localized
            }
        }
    }

    enum UploadDate: Int, CaseIterable {
        case any = 0
        case lastHour = 1
        case today = 2
        case thisWeek = 3
        case thisMonth = 4
        case thisYear = 5

        var displayName: String {
            switch self {
            case .any:
                return "search.date.any".localized
            case .lastHour:
                return "search.date.lastHour".localized
            case .today:
                return "search.date.today".localized
            case .thisWeek:
                return "search.date.thisWeek".localized
            case .thisMonth:
                return "search.date.thisMonth".localized
            case .thisYear:
                return "search.date.thisYear".localized
            }
        }
    }

    enum ContentType: Int, CaseIterable {
        case any = 0
        case video = 1
        case channel = 2
        case playlist = 3

        var displayName: String {
            switch self {
            case .any:
                return "search.type.any".localized
            case .video:
                return "search.type.video".localized
            case .channel:
                return "search.type.channel".localized
            case .playlist:
                return "search.type.playlist".localized
            }
        }
    }

    enum Duration: Int, CaseIterable {
        case any = 0
        case short = 1
        case long = 2
        case medium = 3

        var displayName: String {
            switch self {
            case .any:
                return "search.duration.any".localized
            case .short:
                return "search.duration.short".localized
            case .long:
                return "search.duration.long".localized
            case .medium:
                return "search.duration.medium".localized
            }
        }
    }

    var sort: Sort = .relevance
    var uploadDate: UploadDate = .any
    var type: ContentType = .any
    var duration: Duration = .any

    var isDefault: Bool { self == SearchFilters() }

    /// Base64 protobuf for the /search request; nil when nothing is set.
    /// Schema: field 1 varint = sort; field 2 message { 1 = upload date,
    /// 2 = type, 3 = duration }. Every value fits a single varint byte.
    var encodedParams: String? {
        guard !isDefault else {
            return nil
        }
        var bytes: [UInt8] = []
        if sort != .relevance {
            bytes += [0x08, UInt8(sort.rawValue)]
        }
        var inner: [UInt8] = []
        if uploadDate != .any {
            inner += [0x08, UInt8(uploadDate.rawValue)]
        }
        if type != .any {
            inner += [0x10, UInt8(type.rawValue)]
        }
        if duration != .any {
            inner += [0x18, UInt8(duration.rawValue)]
        }
        if !inner.isEmpty {
            bytes += [0x12, UInt8(inner.count)] + inner
        }
        return Data(bytes).base64EncodedString()
    }
}

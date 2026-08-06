import Foundation

/// Recent search queries, most recent first,
/// persisted in UserDefaults.
final class SearchHistoryStore {
    static let shared = SearchHistoryStore()
    private static let maxEntries = 20
    private let defaults: UserDefaults

    private(set) lazy var queries: [String] = defaults
        .stringArray(forKey: UserDefaultsKeys.Search.history) ?? []

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func add(_ query: String) {
        let trimmed = query.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        guard !trimmed.isEmpty else {
            return
        }
        queries.removeAll {
            $0.caseInsensitiveCompare(trimmed) == .orderedSame
        }
        queries.insert(trimmed, at: 0)
        if queries.count > Self.maxEntries {
            queries = Array(queries.prefix(Self.maxEntries))
        }
        persist()
    }

    func remove(_ query: String) {
        queries.removeAll { $0 == query }
        persist()
    }

    func clear() {
        queries = []
        persist()
    }

    private func persist() {
        defaults.set(
            queries,
            forKey: UserDefaultsKeys.Search.history
        )
    }
}

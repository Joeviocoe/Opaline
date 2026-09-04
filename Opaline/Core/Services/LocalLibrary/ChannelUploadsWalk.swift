import Foundation

/// One traversal's state. A class so each asynchronous hop mutates the same
/// walk rather than copying it forward through the closures.
final class ChannelUploadsWalk {
    var remaining: [String]
    var results: [String: [Video]] = [:]
    let total: Int
    let includeShorts: Bool
    let started = Date()
    let completion: ([String: [Video]]) -> Void
    /// Callers that joined this walk after it started.
    var waiters: [([String: [Video]]) -> Void] = []

    init(
        remaining: [String],
        total: Int,
        includeShorts: Bool,
        completion: @escaping ([String: [Video]]) -> Void
    ) {
        self.remaining = remaining
        self.total = total
        self.includeShorts = includeShorts
        self.completion = completion
    }
}

import Foundation

enum ScreenVisitTracker {
    private static var visited = Set<String>()

    static func hasVisited(_ key: String) -> Bool {
        visited.contains(key)
    }

    static func markVisited(_ key: String) {
        visited.insert(key)
    }

    static func reset() {
        visited.removeAll()
    }
}

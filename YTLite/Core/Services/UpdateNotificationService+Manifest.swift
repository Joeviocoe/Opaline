import Foundation

// Pure helpers behind `UpdateNotificationService`'s manifest parsing —
// split out of that file to keep both under the 300-line limit.

// MARK: - Manifest parsing

/// Flattens the manifest's markdown release notes into plain text — links
/// keep their label, headings and bullet markers become plain lines.
func plainText(_ markdown: String) -> String {
    let lines = markdown.components(separatedBy: .newlines).map { line -> String in
        line
            .replacingOccurrences(
                of: "\\[([^\\]]+)\\]\\([^)]+\\)", with: "$1", options: .regularExpression
            )
            .replacingOccurrences(of: "^\\s*#{1,6}\\s*", with: "", options: .regularExpression)
            .replacingOccurrences(of: "^\\s*[-*]\\s+", with: "• ", options: .regularExpression)
            .replacingOccurrences(of: "\\*\\*|__", with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespaces)
    }
    return lines
        .joined(separator: "\n")
        .replacingOccurrences(of: "\n{3,}", with: "\n\n", options: .regularExpression)
        .trimmingCharacters(in: .whitespacesAndNewlines)
}

/// Guards the case where the app sat unopened for months: an announcement
/// published after install but long past is no longer worth surfacing.
func isStaleAnnouncement(_ date: Date) -> Bool {
    Date().timeIntervalSince(date) >= UpdateNotificationService.maxAnnouncementAge
}

/// When this build first ran — stamped on the first check, so an install
/// never inherits the news published before it.
func featureInstallDate() -> Date {
    let key = UserDefaultsKeys.Notifications.featureInstallDate
    if let stored = UserDefaults.standard.object(forKey: key) as? Date {
        return stored
    }
    let now = Date()
    UserDefaults.standard.set(now, forKey: key)
    return now
}

/// `release-1.6.5` → `1.6.5`; nil for non-release announcements.
func releaseVersion(from identifier: String) -> String? {
    let prefix = "release-"
    guard identifier.hasPrefix(prefix) else {
        return nil
    }
    return String(identifier.dropFirst(prefix.count))
}

/// Numeric, component-wise version comparison ("1.6.10" > "1.6.9").
func isVersion(_ lhs: String, greaterThan rhs: String) -> Bool {
    let lhsParts = lhs.split(separator: ".").map { Int($0) ?? 0 }
    let rhsParts = rhs.split(separator: ".").map { Int($0) ?? 0 }
    let count = max(lhsParts.count, rhsParts.count)
    for index in 0..<count {
        let leftValue = index < lhsParts.count ? lhsParts[index] : 0
        let rightValue = index < rhsParts.count ? rhsParts[index] : 0
        if leftValue != rightValue {
            return leftValue > rightValue
        }
    }
    return false
}

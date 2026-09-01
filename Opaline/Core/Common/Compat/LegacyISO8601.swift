import Foundation

#if LEGACY_IOS9
// ISO8601DateFormatter is iOS 10. Shadowed by name so the two call sites --
// YouTube's RSS <published> and the update feed's "date" -- stay unedited.
//
// Its default is .withInternetDateTime, i.e. RFC 3339: a zone of either "Z" or
// "+HH:MM", and no fractional seconds. `XXXXX` accepts both spellings of the
// zone, and the fractional variant is tried first so a feed that includes
// milliseconds still parses instead of silently returning nil.
//
// en_US_POSIX is not optional: without it a user whose region uses a non-
// Gregorian calendar (Buddhist, Japanese) parses these dates wrongly, and it is
// the kind of bug that only ever appears on someone else's device.
final class ISO8601DateFormatter {
    private static let formats = [
        "yyyy-MM-dd'T'HH:mm:ss.SSSXXXXX",
        "yyyy-MM-dd'T'HH:mm:ssXXXXX",
    ]

    private let formatters: [DateFormatter]

    init() {
        formatters = Self.formats.map { format in
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.calendar = Calendar(identifier: .gregorian)
            formatter.timeZone = TimeZone(secondsFromGMT: 0)
            formatter.dateFormat = format
            return formatter
        }
    }

    func date(from string: String) -> Date? {
        for formatter in formatters {
            if let date = formatter.date(from: string) {
                return date
            }
        }
        return nil
    }

    func string(from date: Date) -> String {
        // Emit the plain form; the fractional one is only ever an input.
        formatters[1].string(from: date)
    }
}
#endif

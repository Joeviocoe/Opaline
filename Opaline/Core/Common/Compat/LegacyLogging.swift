import Foundation

#if LEGACY_IOS9
// os_log and its OSLog/OSLogType companions are iOS 10. Only the share
// extension uses them; shadowing the three names keeps it compiling unchanged.
//
// NSLog is the destination rather than AppLog: this code also builds as a
// separate extension target, where the app's logger is not linked.

struct OSLog {
    let subsystem: String
    let category: String

    init(subsystem: String, category: String) {
        self.subsystem = subsystem
        self.category = category
    }
}

enum OSLogType {
    case `default`, info, debug, error, fault
}

/// `dso` is accepted and ignored, as the real signature's default makes it
/// invisible at call sites anyway.
func os_log(
    _ message: StaticString,
    dso: UnsafeRawPointer? = nil,
    log: OSLog = OSLog(subsystem: "", category: ""),
    type: OSLogType = .default,
    _ args: CVarArg...
) {
    // NSLog does not understand os_log's privacy annotations, and left in place
    // they would print literally.
    let format = "\(message)"
        .replacingOccurrences(of: "%{public}", with: "%")
        .replacingOccurrences(of: "%{private}", with: "%")
    NSLogv("[\(log.category)] " + format, getVaList(args))
}
#endif

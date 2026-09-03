import Darwin
import Foundation
import UIKit

#if LEGACY_IOS9
/// Crash breadcrumbs and memory reporting for the armv7 bring-up.
///
/// The reason this exists: **on armv7 a `SIGTRAP` *is* an integer trap.** Swift
/// traps rather than truncates on a narrowing conversion, and `Int` is 32-bit
/// here, so any missed narrowing in code that parses untrusted bytes — the SABR
/// readers especially — kills the process. Without a breadcrumb that looks
/// identical to a dyld failure, a jetsam and a plain bug: the app is simply
/// gone, and iOS 9 writes no crash log for some of those cases.
enum LegacyDiagnostics {
    private static var started = false
    /// Opened once, up front, and never closed: a signal handler cannot open a
    /// file (not async-signal-safe), so the descriptor has to exist before the
    /// crash does.
    private static var breadcrumbFD: Int32 = -1
    /// High-water mark, so growth over a session is visible rather than inferred
    /// from whichever sample happened to be logged last.
    private static var peakMegabytes = 0

    static func install() {
        guard !started else { return }
        started = true
        openBreadcrumbFile()
        installSignalHandlers()
        logEnvironment()
        startMemorySampler()
    }

    /// stderr alone is not enough. A SpringBoard-launched app on iOS 9 has no
    /// stderr anywhere the syslog can see, so the first version of this wrote
    /// its breadcrumbs into the void -- a SIGABRT was diagnosed only because the
    /// system crash report happened to carry the backtrace. AppLog's own file is
    /// somewhere that survives and can be pulled off the device.
    private static func openBreadcrumbFile() {
        breadcrumbFD = AppLog.currentLogURL.withUnsafeFileSystemRepresentation { path in
            guard let path = path else { return -1 }
            return open(path, O_WRONLY | O_APPEND | O_CREAT, 0o644)
        }
    }

    // MARK: - Signals

    /// Handlers must be async-signal-safe, which rules out Foundation, string
    /// interpolation and any allocation. `write(2)` on a fixed buffer is the
    /// only thing used here. stderr reaches the device syslog, so
    /// `devlog.sh app` picks these up.
    private static func installSignalHandlers() {
        for number in [SIGTRAP, SIGILL, SIGSEGV, SIGBUS, SIGFPE, SIGABRT] {
            signal(number) { caught in
                LegacyDiagnostics.emit(caught)
                // Restore the default and re-raise, so the process still dies
                // the way it would have and any crash reporter still sees it.
                signal(caught, SIG_DFL)
                raise(caught)
            }
        }
    }

    private static func emit(_ number: Int32) {
        var buffer = [UInt8]()
        buffer.reserveCapacity(48)
        for byte in "OPALINE FATAL SIGNAL ".utf8 { buffer.append(byte) }
        // Two digits, written by hand: no allocation, no formatting.
        buffer.append(UInt8(48 + (Int(number) / 10) % 10))
        buffer.append(UInt8(48 + Int(number) % 10))
        if number == SIGTRAP {
            // Any Swift runtime trap lands here -- an Int overflow on this
            // 32-bit target, but equally a force-unwrapped nil, an out-of-range
            // index, or a fatalError. The crash report says which.
            for byte in " (SIGTRAP: a Swift runtime trap - overflow, nil unwrap,"
                .utf8 { buffer.append(byte) }
            for byte in " bounds, or fatalError)".utf8 { buffer.append(byte) }
        }
        buffer.append(0x0A)
        buffer.withUnsafeBufferPointer { pointer in
            // Both destinations: stderr for a shell-launched run, the log file
            // for a SpringBoard-launched one, which is the case that matters.
            _ = write(STDERR_FILENO, pointer.baseAddress, pointer.count)
            if breadcrumbFD >= 0 {
                _ = write(breadcrumbFD, pointer.baseAddress, pointer.count)
            }
        }
    }

    // MARK: - Environment

    private static func logEnvironment() {
        var name = utsname()
        uname(&name)
        let machine = withUnsafePointer(to: &name.machine) { pointer in
            pointer.withMemoryRebound(to: CChar.self, capacity: 1) { String(cString: $0) }
        }
        let memory = ProcessInfo.processInfo.physicalMemory / (1024 * 1024)
        let screen = UIScreen.main
        AppLog.perf(
            "legacy build — \(machine), \(memory) MB, "
                + "\(Int(screen.bounds.width))x\(Int(screen.bounds.height))@\(Int(screen.scale))x, "
                + "Int is \(MemoryLayout<Int>.size * 8)-bit"
        )
    }

    // MARK: - Memory

    /// At 1 GB with 2048×1536 thumbnails, jetsam is the likeliest way this
    /// build dies. Sampling makes that visible as a trend instead of a
    /// disappearance.
    private static func startMemorySampler() {
        let timer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { _ in
            guard let megabytes = residentMegabytes() else { return }
            // Report the trend, not just the level. The plan assumed memory
            // pressure on this 1 GB device; measurement says otherwise (76-78 MB
            // in a long session), so the caps it called for are not justified
            // yet. A rising high-water mark is what would justify them, and this
            // is what would show it.
            if megabytes > peakMegabytes {
                peakMegabytes = megabytes
                AppLog.perf("rss \(megabytes) MB (new peak)")
            } else {
                AppLog.perf("rss \(megabytes) MB (peak \(peakMegabytes) MB)")
            }
        }
        RunLoop.main.add(timer, forMode: .common)
    }

    static func residentMegabytes() -> Int? {
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(
            MemoryLayout<mach_task_basic_info>.size / MemoryLayout<natural_t>.size
        )
        let result = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { raw in
                task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), raw, &count)
            }
        }
        guard result == KERN_SUCCESS else { return nil }
        return Int(info.resident_size / (1024 * 1024))
    }
}
#endif

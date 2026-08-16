import Foundation

// MARK: - Throttling signature on the SABR URL

extension SABRDelivery {
    /// The TV client's streaming URL carries an `n` throttling challenge that
    /// android_vr's does not: unsolved, googlevideo answers 403 before the SABR
    /// protocol says anything. Solve it — on-device where the JS engine can
    /// parse base.js, remotely on iOS 12/13 — and swap it into the URL.
    ///
    /// Anything without an `n` passes straight through, so this costs the
    /// android_vr path nothing.
    static func solvingThrottle(
        _ url: URL,
        resolver: HLSStreamResolver = .shared,
        completion: @escaping (URL) -> Void
    ) {
        guard let unsolved = MWebSource.nValue(of: url) else {
            completion(url)
            return
        }
        SignatureTimestampService.shared.tvPlayerPath { jsPath in
            resolver.solveN(unsolved: unsolved, jsPath: jsPath) { solved in
                guard let solved else {
                    AppLog.player("sabr: n solve failed, sending the URL as-is")
                    completion(url)
                    return
                }
                AppLog.player("sabr: n solved")
                completion(MWebSource.replacingN(in: url, solved: solved))
            }
        }
    }
}

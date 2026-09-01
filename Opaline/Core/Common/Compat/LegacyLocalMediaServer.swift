import Foundation

#if LEGACY_IOS9
/// Compile-only stand-in for the SABR local HTTP sink.
///
/// The real one is built on Network.framework's `NWListener`, which is iOS 12 --
/// the only genuine compile blocker in the tree, and the reason those two files
/// are the entire exclusion list. Everything else about SABR is portable and
/// stays compiled.
///
/// The initialiser fails, deliberately. `withServer` already handles a nil
/// server by reporting no base URL, so SABR degrades to "this delivery cannot
/// serve" rather than pretending to work and stalling playback. The replacement
/// sink is an AVAssetResourceLoaderDelegate on a custom scheme, which needs no
/// listener and no loopback socket at all.
final class LocalMediaServer {
    typealias Handler = (
        _ path: String,
        _ completion: @escaping (Data?, String) -> Void
    ) -> Void

    private(set) var port: UInt16?

    init?(handler: @escaping Handler) {
        return nil
    }

    func start(completion: @escaping (URL?) -> Void) {
        completion(nil)
    }

    func stop() {}
}
#endif

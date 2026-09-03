import Foundation

#if LEGACY_IOS9
/// The SABR HTTP sink, on the loopback server the composition path already uses.
///
/// The real one is built on Network.framework's `NWListener`, which is iOS 12 --
/// the only genuine compile blocker in the tree, and the reason those two files
/// are the entire exclusion list. Everything else about SABR is portable and
/// stays compiled.
///
/// This was a deliberately failing stub until the BSD-socket loopback server
/// grew a generated-content mode. The two servers want different things -- that
/// one proxies byte ranges of a remote URL, this one asks a handler to build a
/// body -- so the server takes a handler alongside its published streams, and
/// SABR's playlists and transmuxed segments come back through it.
final class LocalMediaServer {
    typealias Handler = (
        _ path: String,
        _ completion: @escaping (Data?, String) -> Void
    ) -> Void

    private(set) var port: UInt16?
    private let handler: Handler
    private var started = false

    init?(handler: @escaping Handler) {
        self.handler = handler
    }

    func start(completion: @escaping (URL?) -> Void) {
        // The handler is registered against the shared server, so a second
        // start would replace the first delivery's routing rather than add to
        // it. Deliveries are serial, but say so if that ever stops being true.
        if started {
            AppLog.player("sabr sink: started twice; the later route wins")
        }
        started = true
        let base = LegacyLoopbackServer.shared.publishHandler { path, done in
            self.handler(path, done)
        }
        if base == nil {
            AppLog.player("sabr sink: loopback server would not start")
        }
        completion(base)
    }

    func stop() {
        guard started else { return }
        started = false
        LegacyLoopbackServer.shared.withdrawHandler()
    }
}
#endif

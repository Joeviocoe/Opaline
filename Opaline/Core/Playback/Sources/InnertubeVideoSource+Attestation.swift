import Foundation

// MARK: - Proving the client to the stream server

extension InnertubeVideoSource {
    /// A television has to prove itself before the stream server will serve
    /// it; the anonymous clients are taken as they are. The token binds to
    /// what the client names, and goes on to sign every SABR request.
    func mintingTokenIfNeeded(_ completion: @escaping (String?) -> Void) {
        guard let binding = client.attestationBinding else {
            sabrPoToken = nil
            completion(nil)
            return
        }
        poTokenProvider.fetchSessionToken(
            identifier: binding, client: client.name
        ) { [weak self] result in
            guard let token = try? result.get() else {
                AppLog.player("tv: no pot minted, playback will likely be refused")
                self?.sabrPoToken = nil
                completion(nil)
                return
            }
            self?.sabrPoToken = SABRDelivery.decodeConfig(token)
            completion(token)
        }
    }
}

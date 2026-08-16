import Foundation

// MARK: - Proving the client to the stream server

extension AndroidVRSource {
    /// A television has to prove itself before the stream server will serve it;
    /// android_vr is trusted as it stands. The token binds to this install's
    /// living-room id, and the same one goes on to sign every SABR request.
    func mintingTokenIfNeeded(_ completion: @escaping (String?) -> Void) {
        guard case .tv = client else {
            SABRRequest.poToken = nil
            completion(nil)
            return
        }
        let binding = TVDeviceIdentity.livingRoomPoTokenId
        poTokenProvider.fetchSessionToken(identifier: binding, client: "TVHTML5") { result in
            guard let token = try? result.get() else {
                AppLog.player("tv: no pot minted, playback will likely be refused")
                SABRRequest.poToken = nil
                completion(nil)
                return
            }
            SABRRequest.poToken = SABRDelivery.decodeConfig(token)
            completion(token)
        }
    }
}

import Foundation

// MARK: - Who the SABR session says it is
//
// `clientInfo` has to name the same client the /player call did: the server
// signs and sizes what it serves from it.

extension SABRRequest {
    /// Describes the client the SABR URL was minted for — it has to match the
    /// /player call, the server reads this to size and sign what it serves.
    static func clientInfo(identity: SABRIdentity) -> Data {
        switch identity.client {
        case .tv:
            return tvClientInfo()
        case .visionOS:
            return visionOSClientInfo()
        default:
            return androidVRClientInfo()
        }
    }

    /// What a Vision Pro sends. Same shape as the others; the make, model and
    /// os are what separate a session that is served past the first minute
    /// from one that is not.
    private static func visionOSClientInfo() -> Data {
        var info = Protobuf.string(12, "Apple")
        info += Protobuf.string(13, "RealityDevice14,1")
        info += Protobuf.int(16, 101)
        info += Protobuf.string(17, DirectPlaybackClient.visionOS.clientVersion)
        info += Protobuf.string(18, "visionOS")
        info += Protobuf.string(19, "1.0.2.21O209")
        info += Protobuf.string(21, "en-US")
        info += Protobuf.string(22, "US")
        info += Protobuf.int(37, 1_920)
        info += Protobuf.int(38, 1_080)
        info += Protobuf.int(41, 1)
        info += Protobuf.int(46, 2)
        info += Protobuf.int(55, 1_920)
        info += Protobuf.int(56, 1_080)
        info += Protobuf.float(65, 1.0)
        return info
    }

    private static func tvClientInfo() -> Data {
        var info = Protobuf.int(16, 7)
        info += Protobuf.string(17, DirectPlaybackClient.tv.clientVersion)
        info += Protobuf.string(18, "Cobalt")
        info += Protobuf.string(19, "22.lts.3.306369-gold")
        info += Protobuf.string(21, "en-US")
        info += Protobuf.string(22, "US")
        info += Protobuf.int(37, 1_920)
        info += Protobuf.int(38, 1_080)
        info += Protobuf.int(41, 1)
        info += Protobuf.int(46, 2)
        info += Protobuf.int(55, 1_920)
        info += Protobuf.int(56, 1_080)
        info += Protobuf.float(65, 1.0)
        return info
    }

    private static func androidVRClientInfo() -> Data {
        var info = Protobuf.string(12, "Oculus")
        info += Protobuf.string(13, "Quest 3")
        info += Protobuf.int(16, 28)
        info += Protobuf.string(17, DirectPlaybackClient.androidVR.clientVersion)
        info += Protobuf.string(18, "Android")
        info += Protobuf.string(19, "12L")
        info += Protobuf.string(21, "en-US")
        info += Protobuf.string(22, "US")
        info += Protobuf.int(37, 1_920)
        info += Protobuf.int(38, 1_080)
        info += Protobuf.int(41, 1)
        info += Protobuf.int(46, 2)
        info += Protobuf.int(55, 1_920)
        info += Protobuf.int(56, 1_080)
        info += Protobuf.float(65, 1.0)
        return info
    }
}

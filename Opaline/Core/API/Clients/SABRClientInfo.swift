import Foundation

/// The part of a SABR `clientInfo` every client sends the same way: locale,
/// screen and density. Only the make, model, os and version above it differ.
enum SABRClientInfo {
    static func commonTail() -> Data {
        var info = Protobuf.string(21, "en-US")
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

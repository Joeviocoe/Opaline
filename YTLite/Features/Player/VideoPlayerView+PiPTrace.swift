import AVKit
import UIKit

// MARK: - PiP Tracing

extension VideoPlayerView {
    /// PiP fails silently, differently on every iOS version, and only for
    /// people we cannot debug live — so every branch of the start path leaves
    /// a line in the shipped log. A bug report then starts from the exported
    /// log instead of a day of questions (#31).
    func pipTrace(_ event: String) {
        let pip = pipController
        AppLog.player(
            "PiP \(event): supported=\(isPiPAvailable) controller=\(pip != nil) "
                + "active=\(pip?.isPictureInPictureActive ?? false) "
                + "possible=\(pip?.isPictureInPicturePossible ?? false) "
                + "ready=\(playerLayer.isReadyForDisplay) "
                + "layerPlayer=\(playerLayer.player != nil) "
                + "rate=\(player?.rate ?? 0) auto=\(isAutoPiPEnabled)"
        )
    }
}

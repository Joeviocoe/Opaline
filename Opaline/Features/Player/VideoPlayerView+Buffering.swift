import AVFoundation
import UIKit

// MARK: - Buffering indicator

extension VideoPlayerView {
    /// AVPlayer passes through `waitingToPlayAtSpecifiedRate` on nearly every
    /// `play()`, buffered or not — showing the spinner (and hiding the
    /// transport buttons) right then makes a resume flicker like a stall.
    /// Only a wait that outlives the grace period is a real one.
    func scheduleBufferingIndicator() {
        bufferingIndicatorWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self = self,
                  self.player?.timeControlStatus == .waitingToPlayAtSpecifiedRate else {
                return
            }
            #if LEGACY_IOS9
            AppLog.player("buffering: spinner shown (controls hidden)")
            #endif
            self.spinner.startAnimating()
            self.setCenter(hidden: true)
        }
        bufferingIndicatorWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4, execute: work)
    }

    func hideBufferingIndicator() {
        #if LEGACY_IOS9
        if spinner.isAnimating {
            AppLog.player("buffering: spinner hidden")
        }
        #endif
        bufferingIndicatorWork?.cancel()
        spinner.stopAnimating()
        setCenter(hidden: false)
    }
}

import UIKit

/// Ten selectors for ten digits.
///
/// There is no way to tell two commands apart from a single action on this
/// deployment target: `UIKeyCommand.propertyList` is iOS 13, and `UIPress.key`
/// — which would carry the character — is iOS 13.4. So each digit gets its own
/// entry point, and speed lives here too rather than pushing the transport file
/// over the file-length limit.
extension WatchViewController {
    @objc
    func keyboardScrub0() { videoPlayerView?.keyboardScrub(toTenth: 0) }

    @objc
    func keyboardScrub1() { videoPlayerView?.keyboardScrub(toTenth: 1) }

    @objc
    func keyboardScrub2() { videoPlayerView?.keyboardScrub(toTenth: 2) }

    @objc
    func keyboardScrub3() { videoPlayerView?.keyboardScrub(toTenth: 3) }

    @objc
    func keyboardScrub4() { videoPlayerView?.keyboardScrub(toTenth: 4) }

    @objc
    func keyboardScrub5() { videoPlayerView?.keyboardScrub(toTenth: 5) }

    @objc
    func keyboardScrub6() { videoPlayerView?.keyboardScrub(toTenth: 6) }

    @objc
    func keyboardScrub7() { videoPlayerView?.keyboardScrub(toTenth: 7) }

    @objc
    func keyboardScrub8() { videoPlayerView?.keyboardScrub(toTenth: 8) }

    @objc
    func keyboardScrub9() { videoPlayerView?.keyboardScrub(toTenth: 9) }

    @objc
    func keyboardSlowDown() {
        videoPlayerView?.keyboardNudgeSpeed(faster: false)
    }

    @objc
    func keyboardSpeedUp() {
        videoPlayerView?.keyboardNudgeSpeed(faster: true)
    }
}

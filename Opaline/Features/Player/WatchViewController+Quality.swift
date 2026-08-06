import UIKit

// MARK: - Quality picker
//
// Fully source-driven: the active `VideoSource` owns its quality options and how
// switching works. No source-specific (DASH/itag) logic here.

extension WatchViewController {
    func showQualityPicker() {
        guard let source = playbackFacade.activeVideoSource,
              source.supportsQualitySelection else {
            return
        }
        showSourceQualityPicker(source: source)
    }
}

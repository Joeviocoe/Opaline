import UIKit

extension UIViewController {
    /// Asks UIKit to re-read `supportedInterfaceOrientations`.
    ///
    /// It caches the mask and otherwise only refreshes it on its own schedule,
    /// so any code that widens or narrows the mask by itself — collapsing the
    /// player panel, lifting a fullscreen orientation lock — has to say so, or
    /// the interface stays stuck at whatever the mask used to allow.
    func refreshSupportedOrientations() {
        if #available(iOS 16.0, *) {
            setNeedsUpdateOfSupportedInterfaceOrientations()
        } else {
            UIViewController.attemptRotationToDeviceOrientation()
        }
    }
}

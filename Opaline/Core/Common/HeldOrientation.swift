import UIKit

/// The orientation the device is actually being held in.
///
/// `UIDevice.orientation` reports instantaneous tilt: a phone held slightly
/// reclined reads `.faceUp` however sideways it looks, and the reading flickers
/// between the two while it merely sits in a hand. Code that has to answer "how
/// is this being held right now" wants the last real reading, not the current
/// one — and, because generation is refcounted and starts cold, wants it to
/// have been running long before the question is asked.
enum HeldOrientation {
    private static var lastReal: UIDeviceOrientation = .portrait

    /// The live reading whenever it says anything, the last real one otherwise.
    ///
    /// Notifications alone are not enough: a phone picked up sideways and held
    /// still never *changes* orientation, so nothing is ever posted and the
    /// stored answer would sit at its launch default forever.
    static var current: UIDeviceOrientation {
        let device = UIDevice.current.orientation
        return device.isPortrait || device.isLandscape ? device : lastReal
    }

    /// Called once at launch; generation then stays on for the app's lifetime.
    static func startTracking() {
        UIDevice.current.beginGeneratingDeviceOrientationNotifications()
        NotificationCenter.default.addObserver(
            forName: UIDevice.orientationDidChangeNotification,
            object: nil,
            queue: .main
        ) { _ in
            let device = UIDevice.current.orientation
            // `.faceUp`, `.faceDown` and `.unknown` say nothing about which way
            // the device is turned, so they leave the last answer standing.
            guard device.isPortrait || device.isLandscape else {
                return
            }
            lastReal = device
        }
    }
}

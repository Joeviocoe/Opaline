import UIKit

#if LEGACY_IOS9
// UIGraphicsImageRenderer is iOS 10. Declaring a type of the same name in this
// module shadows UIKit's for the whole target, so the 10 call sites compile
// unchanged and upstream can keep editing them freely -- which is the entire
// reason for doing it this way rather than renaming them.
//
// The pre-10 equivalent is the UIGraphicsBeginImageContextWithOptions stack.
// Scale 0 means "this screen's scale", matching the renderer's default format,
// and opaque: false matches its default too.

/// Stands in for `UIGraphicsImageRendererContext`.
final class UIGraphicsImageRendererContext {
    let cgContext: CGContext

    init(cgContext: CGContext) {
        self.cgContext = cgContext
    }

    /// Fills with the colour most recently sent `setFill()`, as UIKit's does.
    func fill(_ rect: CGRect) {
        cgContext.fill(rect)
    }

    func stroke(_ rect: CGRect) {
        cgContext.stroke(rect)
    }

    func clip(to rect: CGRect) {
        cgContext.clip(to: rect)
    }
}

/// Stands in for `UIGraphicsImageRenderer`.
final class UIGraphicsImageRenderer {
    private let size: CGSize
    private let opaque: Bool
    private let scale: CGFloat

    init(size: CGSize) {
        self.size = size
        opaque = false
        scale = 0
    }

    init(size: CGSize, opaque: Bool, scale: CGFloat = 0) {
        self.size = size
        self.opaque = opaque
        self.scale = scale
    }

    func image(_ actions: (UIGraphicsImageRendererContext) -> Void) -> UIImage {
        UIGraphicsBeginImageContextWithOptions(size, opaque, scale)
        defer { UIGraphicsEndImageContext() }
        guard let cgContext = UIGraphicsGetCurrentContext() else {
            // A zero or negative size yields no context. The renderer returns an
            // empty image rather than trapping, so match that.
            return UIImage()
        }
        actions(UIGraphicsImageRendererContext(cgContext: cgContext))
        return UIGraphicsGetImageFromCurrentImageContext() ?? UIImage()
    }
}
#endif

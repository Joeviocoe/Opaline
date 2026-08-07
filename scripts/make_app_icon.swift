// Cuts the app icon, the launch mark and the README logo out of the designer's artwork.
//
// One input for every mode: the transparent triangle. The v2 mark carries the opal gradient
// inside the shape, so an icon is just that triangle on a flat background — which is also
// the only way to place it freely, since the designer's own light/dark files bake in a soft
// shadow that spreads across the whole canvas and leaves a visible seam if repositioned.
//
//   light   -> every icon size, triangle on the light background
//   dark    -> the 1024 dark icon (iOS scales the rest down itself)
//   launch  -> SplashMark, the triangle alone, cropped tight
//   rounded -> logo.png for the README, corners already cut
//
// Must be compiled, not run through the `swift` interpreter — the JIT can't resolve
// CGContext.draw(_:in:):
//
//   swiftc -O -o /tmp/mkicon scripts/make_app_icon.swift
//   /tmp/mkicon <Without Background Logo.png> Opaline/Assets.xcassets/AppIcon.appiconset light
//   /tmp/mkicon <Without Background Logo.png> Opaline/Assets.xcassets/AppIcon.appiconset dark
//   /tmp/mkicon <Without Background Logo.png> Opaline/Assets.xcassets/SplashMark.imageset launch
//   /tmp/mkicon <Without Background Logo.png> source rounded
//   /tmp/mkicon <Without Background Logo.png> source rounded-dark

import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

let sizes: [(String, Int)] = [
    ("Icon-20@1x", 20), ("Icon-20@2x", 40), ("Icon-20@3x", 60),
    ("Icon-29@1x", 29), ("Icon-29@2x", 58), ("Icon-29@3x", 87),
    ("Icon-40@1x", 40), ("Icon-40@2x", 80), ("Icon-40@3x", 120),
    ("Icon-60@2x", 120), ("Icon-60@3x", 180),
    ("Icon-76@1x", 76), ("Icon-76@2x", 152),
    ("Icon-83.5@2x", 167),
    ("Icon-1024", 1024),
]

/// The dark file is declared once at 1024 and iOS scales it down itself, so the smaller
/// dark sizes would only sit in the catalog unassigned.
let darkSuffix = "-dark"
let darkOnlySize = 1024

/// The designer's backgrounds, sampled from their light and dark exports — near-white and
/// near-black rather than pure, which is what keeps the icon from looking like a hole.
let lightBackground = (245.0, 248.0, 250.0)
let darkBackground = (15.0, 15.0, 16.0)

/// The triangle's share of the icon's width. The mark fills its own canvas edge to edge, and
/// at that size it reads as oversized on a home screen; 0.55 is what the pre-v2 icon used.
let markWidth = 0.55

/// "rounded" writes the one file iOS never renders for us: the icon with its corners
/// already cut, for READMEs and web pages. 0.2237 of the side is Apple's own superellipse
/// ratio; a plain rounded rect at that radius is indistinguishable at README sizes.
let roundedSide = 512
let cornerRatio = 0.2237

/// Splash mark widths per scale. Both the launch storyboard and the splash draw the mark at
/// 15% of the screen width, so even a 1024pt iPad only asks for ~310px; these leave room.
let launchWidths = [("@1x", 180), ("@2x", 360), ("@3x", 540)]

guard CommandLine.arguments.count == 4,
      ["light", "dark", "launch", "rounded", "rounded-dark"].contains(CommandLine.arguments[3])
else {
    let modes = "light|dark|launch|rounded|rounded-dark"
    let usage = "usage: make_app_icon.swift <transparent.png> <out.dir> <\(modes)>\n"
    FileHandle.standardError.write(Data(usage.utf8))
    exit(2)
}
let sourceURL = URL(fileURLWithPath: CommandLine.arguments[1])
let outDir = URL(fileURLWithPath: CommandLine.arguments[2])
let mode = CommandLine.arguments[3]
let isDark = mode.hasSuffix("dark")
let isLaunch = mode == "launch"
let isRounded = mode.hasPrefix("rounded")

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data("\(message)\n".utf8))
    exit(1)
}

guard let src = CGImageSourceCreateWithURL(sourceURL as CFURL, nil),
      let loaded = CGImageSourceCreateImageAtIndex(src, 0, nil)
else { fail("cannot read \(sourceURL.path)") }

/// Tight bounds of everything that isn't transparent, so neither the icon nor the storyboard's
/// aspect constraint has to reason about dead margin. The threshold clears the soft shadow the
/// artwork carries, which would otherwise pad the crop by a good 2%.
let alphaThreshold: UInt8 = 40

func opaqueBounds(of image: CGImage) -> CGRect? {
    let width = image.width, height = image.height
    var pixels = [UInt8](repeating: 0, count: width * height * 4)
    guard let ctx = CGContext(
        data: &pixels, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else { return nil }
    ctx.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))

    var minX = width, minY = height, maxX = -1, maxY = -1
    for row in 0 ..< height {
        for col in 0 ..< width where pixels[(row * width + col) * 4 + 3] > alphaThreshold {
            minX = min(minX, col); maxX = max(maxX, col)
            minY = min(minY, row); maxY = max(maxY, row)
        }
    }
    guard maxX >= minX, maxY >= minY else { return nil }
    // cropping(to:) takes top-left origin coordinates, matching the buffer's row order.
    return CGRect(
        x: CGFloat(minX), y: CGFloat(minY),
        width: CGFloat(maxX - minX + 1), height: CGFloat(maxY - minY + 1)
    )
}

func write(_ image: CGImage, to url: URL) {
    guard let dest = CGImageDestinationCreateWithURL(
        url as CFURL, UTType.png.identifier as CFString, 1, nil
    ) else { fail("cannot write \(url.path)") }
    CGImageDestinationAddImage(dest, image, nil)
    guard CGImageDestinationFinalize(dest) else { exit(1) }
}

guard let bounds = opaqueBounds(of: loaded), let mark = loaded.cropping(to: bounds) else {
    fail("cannot crop the mark out of \(loaded.width)x\(loaded.height)")
}
let aspect = Double(mark.height) / Double(mark.width)
print("source \(loaded.width)x\(loaded.height) -> mark \(mark.width)x\(mark.height), \(aspect)")

/// The mark alone, at `width` — transparent, for the splash.
func renderMark(width: Int) -> CGImage? {
    let height = Int((Double(width) * aspect).rounded())
    guard let ctx = CGContext(
        data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else { return nil }
    ctx.interpolationQuality = .high
    ctx.draw(mark, in: CGRect(x: 0, y: 0, width: width, height: height))
    return ctx.makeImage()
}

/// The icon: the mark centred on the flat theme background, optionally with Apple's corners
/// cut. Stays opaque unless rounded — App Store artwork must not carry an alpha channel.
func renderIcon(side: Int, rounded: Bool = false) -> CGImage? {
    let format = rounded ? CGImageAlphaInfo.premultipliedLast : .noneSkipLast
    guard let ctx = CGContext(
        data: nil, width: side, height: side, bitsPerComponent: 8, bytesPerRow: 0,
        space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: format.rawValue
    ) else { return nil }
    ctx.interpolationQuality = .high

    let full = CGRect(x: 0, y: 0, width: side, height: side)
    if rounded {
        ctx.addPath(CGPath(
            roundedRect: full,
            cornerWidth: CGFloat(side) * cornerRatio, cornerHeight: CGFloat(side) * cornerRatio,
            transform: nil
        ))
        ctx.clip()
    }
    let background = isDark ? darkBackground : lightBackground
    ctx.setFillColor(CGColor(
        red: background.0 / 255, green: background.1 / 255, blue: background.2 / 255, alpha: 1
    ))
    ctx.fill(full)

    let width = Double(side) * markWidth, height = width * aspect
    ctx.draw(mark, in: CGRect(
        x: (Double(side) - width) / 2, y: (Double(side) - height) / 2,
        width: width, height: height
    ))
    return ctx.makeImage()
}

if isLaunch {
    for (scale, width) in launchWidths {
        guard let rendered = renderMark(width: width) else { fail("render failed at \(width)") }
        write(rendered, to: outDir.appendingPathComponent("SplashMark\(scale).png"))
        print("SplashMark\(scale).png  \(width)x\(rendered.height)")
    }
    exit(0)
}

if isRounded {
    guard let rendered = renderIcon(side: roundedSide, rounded: true) else {
        fail("render failed at \(roundedSide)")
    }
    let name = isDark ? "logo-dark.png" : "logo.png"
    write(rendered, to: outDir.appendingPathComponent(name))
    print("\(name)  \(roundedSide)x\(roundedSide)")
    exit(0)
}

for (name, side) in sizes where !isDark || side == darkOnlySize {
    guard let rendered = renderIcon(side: side) else { fail("render failed at \(side)") }
    let filename = "\(name)\(isDark ? darkSuffix : "").png"
    write(rendered, to: outDir.appendingPathComponent(filename))
    print("\(filename)  \(side)x\(side)")
}

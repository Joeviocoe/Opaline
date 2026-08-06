// Builds the app icon and launch logo from the finished Logo.png artwork.
//
// The source is a near-square composition (gradient background with a white play
// triangle on it), so "light" is just a centre crop plus resizes. "dark" and "launch"
// lift the triangle off its background with a luminance/saturation mask — the background
// is a saturated gradient and the triangle is near-white, so the two separate cleanly —
// then redraw it on black, or keep it transparent and cropped tight for the launch screen.
//
// Must be compiled, not run through the `swift` interpreter — the JIT can't resolve
// CGContext.draw(_:in:):
//
//   swiftc -O -o /tmp/mkicon scripts/make_app_icon.swift
//   /tmp/mkicon <Logo.png> Opaline/Assets.xcassets/AppIcon.appiconset light
//   /tmp/mkicon <Logo.png> Opaline/Assets.xcassets/AppIcon.appiconset dark
//   /tmp/mkicon <Logo.png> Opaline/Assets.xcassets/SplashMark.imageset launch
//   /tmp/mkicon <Logo.png> source rounded

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

/// A pixel is triangle, not background, when it is this bright and this unsaturated.
/// Both are ramps rather than hard cuts, so the extracted edge keeps its antialiasing.
let lumaRange: (ClosedRange<Double>) = 0.80 ... 0.90
let saturationRange: (ClosedRange<Double>) = 0.03 ... 0.10

func smoothstep(_ range: ClosedRange<Double>, _ value: Double) -> Double {
    let t = min(max((value - range.lowerBound) / (range.upperBound - range.lowerBound), 0), 1)
    return t * t * (3 - 2 * t)
}

guard CommandLine.arguments.count == 4,
      ["light", "dark", "launch", "rounded"].contains(CommandLine.arguments[3])
else {
    let usage = "usage: make_app_icon.swift <Logo.png> <out.dir> <light|dark|launch|rounded>\n"
    FileHandle.standardError.write(Data(usage.utf8))
    exit(2)
}
let sourceURL = URL(fileURLWithPath: CommandLine.arguments[1])
let outDir = URL(fileURLWithPath: CommandLine.arguments[2])
let mode = CommandLine.arguments[3]
let isDark = mode == "dark"
let isLaunch = mode == "launch"
let isRounded = mode == "rounded"

/// "rounded" writes the one file iOS never renders for us: the icon with its corners
/// already cut, for READMEs and web pages. 0.2237 of the side is Apple's own superellipse
/// ratio; a plain rounded rect at that radius is indistinguishable at README sizes.
let roundedSide = 512
let cornerRatio = 0.2237

/// Splash mark widths per scale. Both the launch storyboard and the splash draw the mark at
/// 15% of the screen width, so even a 1024pt iPad only asks for ~310px; these leave room.
let launchWidths = [("@1x", 180), ("@2x", 360), ("@3x", 540)]

guard let src = CGImageSourceCreateWithURL(sourceURL as CFURL, nil),
      let loaded = CGImageSourceCreateImageAtIndex(src, 0, nil)
else {
    FileHandle.standardError.write(Data("cannot read \(sourceURL.path)\n".utf8))
    exit(1)
}

/// Largest centred square of the source.
func squareCrop(_ image: CGImage) -> CGImage? {
    let side = min(image.width, image.height)
    return image.cropping(to: CGRect(
        x: (image.width - side) / 2,
        y: (image.height - side) / 2,
        width: side,
        height: side
    ))
}

/// Same pixels, but alpha replaced by "how much this looks like the white triangle".
func triangleMasked(_ image: CGImage) -> CGImage? {
    let width = image.width, height = image.height
    var pixels = [UInt8](repeating: 0, count: width * height * 4)
    guard let ctx = CGContext(
        data: &pixels, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else { return nil }
    ctx.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))

    for index in stride(from: 0, to: pixels.count, by: 4) {
        let red = Double(pixels[index]) / 255
        let green = Double(pixels[index + 1]) / 255
        let blue = Double(pixels[index + 2]) / 255
        let darkest = min(red, green, blue), brightest = max(red, green, blue)
        let saturation = brightest > 0 ? (brightest - darkest) / brightest : 0

        let alpha = smoothstep(lumaRange, darkest) * (1 - smoothstep(saturationRange, saturation))
        // Premultiplied buffer: the colour channels have to be scaled to match.
        pixels[index] = UInt8(red * alpha * 255)
        pixels[index + 1] = UInt8(green * alpha * 255)
        pixels[index + 2] = UInt8(blue * alpha * 255)
        pixels[index + 3] = UInt8(alpha * 255)
    }
    return ctx.makeImage()
}

/// Tight bounds of everything the mask kept, so the launch logo has no dead margin for
/// the storyboard's aspect constraint to reason about.
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
        for col in 0 ..< width where pixels[(row * width + col) * 4 + 3] > 8 {
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

func render(_ artwork: CGImage, at side: Int) -> CGImage? {
    guard let ctx = CGContext(
        data: nil, width: side, height: side, bitsPerComponent: 8, bytesPerRow: 0,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
    ) else { return nil }
    ctx.interpolationQuality = .high

    let full = CGRect(x: 0, y: 0, width: side, height: side)
    if isDark {
        ctx.setFillColor(CGColor(red: 0, green: 0, blue: 0, alpha: 1))
        ctx.fill(full)
    }
    ctx.draw(artwork, in: full)
    return ctx.makeImage()
}

guard let square = squareCrop(loaded) else {
    FileHandle.standardError.write(Data("cannot crop \(loaded.width)x\(loaded.height)\n".utf8))
    exit(1)
}
let artwork = isDark || isLaunch ? triangleMasked(square) : square
guard let artwork else {
    FileHandle.standardError.write(Data("cannot mask out the triangle\n".utf8))
    exit(1)
}
print("source \(loaded.width)x\(loaded.height) -> square \(square.width)")

func write(_ image: CGImage, to url: URL) {
    guard let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)
    else {
        FileHandle.standardError.write(Data("cannot write \(url.path)\n".utf8))
        exit(1)
    }
    CGImageDestinationAddImage(dest, image, nil)
    guard CGImageDestinationFinalize(dest) else { exit(1) }
}

if isRounded {
    let side = roundedSide
    guard let ctx = CGContext(
        data: nil, width: side, height: side, bitsPerComponent: 8, bytesPerRow: 0,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else { exit(1) }
    ctx.interpolationQuality = .high
    let full = CGRect(x: 0, y: 0, width: side, height: side)
    let path = CGPath(
        roundedRect: full,
        cornerWidth: CGFloat(side) * cornerRatio,
        cornerHeight: CGFloat(side) * cornerRatio,
        transform: nil
    )
    ctx.addPath(path)
    ctx.clip()
    ctx.draw(artwork, in: full)
    guard let rendered = ctx.makeImage() else { exit(1) }
    write(rendered, to: outDir.appendingPathComponent("logo.png"))
    print("logo.png  \(side)x\(side)")
    exit(0)
}

if isLaunch {
    guard let bounds = opaqueBounds(of: artwork), let cropped = artwork.cropping(to: bounds) else {
        FileHandle.standardError.write(Data("cannot crop the launch logo\n".utf8))
        exit(1)
    }
    let aspect = CGFloat(cropped.height) / CGFloat(cropped.width)
    print("launch logo \(cropped.width)x\(cropped.height), height/width = \(aspect)")

    for (scale, width) in launchWidths {
        let height = Int((CGFloat(width) * aspect).rounded())
        guard let ctx = CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { exit(1) }
        ctx.interpolationQuality = .high
        ctx.draw(cropped, in: CGRect(x: 0, y: 0, width: width, height: height))
        guard let rendered = ctx.makeImage() else { exit(1) }
        write(rendered, to: outDir.appendingPathComponent("SplashMark\(scale).png"))
        print("SplashMark\(scale).png  \(width)x\(height)")
    }
    exit(0)
}

for (name, side) in sizes where !isDark || side == darkOnlySize {
    guard let rendered = render(artwork, at: side) else {
        FileHandle.standardError.write(Data("render failed at \(side)\n".utf8))
        exit(1)
    }
    let filename = "\(name)\(isDark ? darkSuffix : "").png"
    write(rendered, to: outDir.appendingPathComponent(filename))
    print("\(filename)  \(side)x\(side)")
}

// Turns an Icon Composer export into a classic full-bleed app icon.
//
//   swift scripts/square_composer_icon.swift <src-1024.png> <out.png> <size> [glyph]
//
// Composer bakes the iOS 26 corner radius into its PNGs, so the corners are
// transparent. Classic icons must be opaque squares — iOS applies its own
// mask, and a baked corner ends up rounded twice with the wallpaper showing
// through. Two passes:
//   1. zoom past the rounded band (1.20 — the curve reaches ~8% in), which
//      also drops the light glass rim. Extending the edge instead would only
//      smear that rim into the corners.
//   2. optionally shrink the now-flat artwork by `glyph` so the mark is not
//      cropped so tight, filling the margin from the nearest opaque pixel.
import AppKit

let src = CommandLine.arguments[1]
let dst = CommandLine.arguments[2]
let size = Int(CommandLine.arguments[3]) ?? 180
let glyph = CommandLine.arguments.count > 4
    ? (Double(CommandLine.arguments[4]) ?? 1) : 1
let zoom = 1.20

guard let img = NSImage(contentsOfFile: src) else { exit(1) }

func canvas(_ side: Int, _ draw: (NSRect) -> Void) -> NSBitmapImageRep {
    guard let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: side, pixelsHigh: side,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0) else { exit(1) }
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    NSGraphicsContext.current?.imageInterpolation = .high
    draw(NSRect(x: 0, y: 0, width: side, height: side))
    NSGraphicsContext.restoreGraphicsState()
    return rep
}

let scale = zoom * glyph
let out = canvas(size) { rect in
    let side = rect.width * scale
    img.draw(in: NSRect(
        x: (rect.width - side) / 2, y: (rect.height - side) / 2,
        width: side, height: side
    ))
}

func opaque(_ rep: NSBitmapImageRep, _ x: Int, _ y: Int) -> NSColor? {
    guard x >= 0, y >= 0, x < size, y < size,
          let c = rep.colorAt(x: x, y: y), c.alphaComponent > 0.99 else { return nil }
    return c
}

if glyph < 1 {
    let source = out.copy() as? NSBitmapImageRep ?? out
    for y in 0..<size {
        for x in 0..<size where opaque(source, x, y) == nil {
            var found: NSColor?
            var r = 1
            while found == nil, r < size {
                for d in -r...r where found == nil {
                    found = opaque(source, x + d, y - r)
                        ?? opaque(source, x + d, y + r)
                        ?? opaque(source, x - r, y + d)
                        ?? opaque(source, x + r, y + d)
                }
                r += 1
            }
            out.setColor(found ?? .black, atX: x, y: y)
        }
    }
}

try? out.representation(using: .png, properties: [:])?
    .write(to: URL(fileURLWithPath: dst))
print("\(dst) \(size)px glyph=\(glyph)")

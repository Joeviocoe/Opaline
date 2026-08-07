// Generates asset-catalog icons from SF Symbols as template PNGs.
//
//   swift scripts/make_icon.swift Opaline/Assets.xcassets [symbol:asset_name ...]
//
// With no pairs it regenerates the whole set defined in `map` below. iOS 12
// has no SF Symbols API, so every icon ships as a pre-rendered template PNG
// at 1x/2x/3x and is tinted at runtime.
//
// Scaling is by the glyph's INK bounding box, not the symbol image's own
// bounds: SF Symbols carry a lot of internal padding, so fitting the image
// bounds leaves the visible glyph far smaller than the canvas and icons look
// shrunken wherever they are drawn at a fixed size. Every icon is normalised
// to `coverage` of the canvas, which is also what keeps the set optically
// consistent.
import AppKit

let out = CommandLine.arguments[1]
let coverage = 0.86  // fraction of the canvas the ink should span
let overrides: [(String, String)] = CommandLine.arguments.dropFirst(2).compactMap {
    let parts = $0.split(separator: ":", maxSplits: 1)
    guard parts.count == 2 else { return nil }
    return (String(parts[0]), String(parts[1]))
}
let fullSet: [(String, String)] = [
    ("gearshape.fill", "icon_Gear"),
    ("gobackward.10", "icon_Gobackward_10"),
    ("goforward.10", "icon_Goforward_10"),
    ("house.fill", "icon_House_Fill"),
    ("magnifyingglass", "icon_Magnifyingglass"),
    ("play.rectangle.fill", "icon_Play_Rectangle"),
    ("play.square.stack.fill", "icon_Square_Stack"),
    ("bell.fill", "icon_bell"),
    ("bookmark", "icon_bookmark"),
    ("square.and.arrow.down", "icon_download"),
    ("person.fill", "icon_person_fill"),
    ("square.and.arrow.up", "icon_share"),
    ("hand.thumbsdown", "icon_thumb_down"),
    ("hand.thumbsup", "icon_thumb_up"),
    ("play.fill", "icon_play_fill"),
    ("text.append", "icon_text_append"),
    ("clock", "icon_clock"),
    ("minus.circle", "icon_minus_circle"),
    ("info.circle", "icon_info_circle"),
    ("arrow.counterclockwise", "icon_replay"),
    ("backward.end.fill", "icon_previous"),
    ("forward.end.fill", "icon_next")
]

/// Renders the symbol huge, then reports the image plus its ink bounds so
/// callers can scale by actual glyph extent instead of the symbol's own
/// generous padding.
func master(_ symbol: String) -> (NSImage, CGRect)? {
    let cfg = NSImage.SymbolConfiguration(pointSize: 256, weight: .regular)
    guard let img = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)?
        .withSymbolConfiguration(cfg) else { return nil }
    let side = 512
    guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: side,
        pixelsHigh: side, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
        isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)
    else { return nil }
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let r = img.size
    let f = min(Double(side) * 0.9 / r.width, Double(side) * 0.9 / r.height)
    let w = r.width * f, h = r.height * f
    img.draw(in: NSRect(x: (Double(side)-w)/2, y: (Double(side)-h)/2, width: w, height: h))
    NSGraphicsContext.restoreGraphicsState()
    var minX = side, maxX = 0, minYTop = side, maxYTop = 0
    for y in 0..<side {
        for x in 0..<side {
            guard let c = rep.colorAt(x: x, y: y), c.alphaComponent > 0.03 else { continue }
            minX = min(minX, x); maxX = max(maxX, x)
            minYTop = min(minYTop, y); maxYTop = max(maxYTop, y)
        }
    }
    guard maxX >= minX else { return nil }
    // colorAt is top-down; drawing is bottom-up.
    let bbox = CGRect(x: Double(minX), y: Double(side - maxYTop - 1),
                      width: Double(maxX - minX + 1), height: Double(maxYTop - minYTop + 1))
    let full = NSImage(size: NSSize(width: side, height: side))
    full.addRepresentation(rep)
    return (full, bbox)
}

func render(_ symbol: String, name: String, rotate: Bool = false) {
    guard let (img, bbox) = master(symbol) else { print("MISSING \(symbol)"); return }
    let dir = "\(out)/\(name).imageset"
    try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
    for f in (try? FileManager.default.contentsOfDirectory(atPath: dir)) ?? []
    where f.hasSuffix(".png") { try? FileManager.default.removeItem(atPath: "\(dir)/\(f)") }
    var entries: [String] = []
    for scale in [1, 2, 3] {
        let side = Double(Int((33.4 * Double(scale)).rounded()))
        guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(side),
            pixelsHigh: Int(side), bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
            isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)
        else { continue }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        // Rotating swaps which ink dimension has to fit the canvas.
        let inkW = rotate ? bbox.height : bbox.width
        let inkH = rotate ? bbox.width : bbox.height
        let k = min(side * coverage / inkW, side * coverage / inkH)
        if rotate {
            NSGraphicsContext.current?.cgContext.translateBy(x: side / 2, y: side / 2)
            NSGraphicsContext.current?.cgContext.rotate(by: .pi / 2)
            NSGraphicsContext.current?.cgContext.translateBy(x: -side / 2, y: -side / 2)
        }
        let drawW = img.size.width * k, drawH = img.size.height * k
        let x = side / 2 - (bbox.midX * k)
        let y = side / 2 - (bbox.midY * k)
        img.draw(in: NSRect(x: x, y: y, width: drawW, height: drawH))
        NSGraphicsContext.restoreGraphicsState()
        guard let png = rep.representation(using: .png, properties: [:]) else { continue }
        let file = "\(name)@\(scale)x.png"
        try? png.write(to: URL(fileURLWithPath: "\(dir)/\(file)"))
        entries.append("{\"filename\":\"\(file)\",\"idiom\":\"universal\",\"scale\":\"\(scale)x\"}")
    }
    let json = "{\"images\":[\(entries.joined(separator: ","))],\"info\":{\"author\":\"xcode\",\"version\":1},\"properties\":{\"template-rendering-intent\":\"template\"}}"
    try? json.write(toFile: "\(dir)/Contents.json", atomically: true, encoding: .utf8)
    print("OK \(symbol) -> \(name)")
}

let map = overrides.isEmpty ? fullSet : overrides
for (s, n) in map { render(s, name: n) }
if overrides.isEmpty {
    // the card menu button wants vertical dots; SF only ships them horizontal
    render("ellipsis", name: "icon_ellipsis_vertical", rotate: true)
}

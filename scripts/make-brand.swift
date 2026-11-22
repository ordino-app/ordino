// Renders ordino's brand PNGs from the SVG sources in brand/.
//   swift scripts/make-brand.swift
// SVGs are the masters; this only exports raster versions for places that need them.
import AppKit

let root = URL(fileURLWithPath: CommandLine.arguments[0]).deletingLastPathComponent().deletingLastPathComponent()
let brand = root.appendingPathComponent("brand")
let out = brand.appendingPathComponent("png")
try? FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)

let paper = NSColor(srgbRed: 0xFB / 255, green: 0xFA / 255, blue: 0xF7 / 255, alpha: 1)
let graphiteTop = NSColor(srgbRed: 0x2B / 255, green: 0x2D / 255, blue: 0x31 / 255, alpha: 1)
let graphiteBottom = NSColor(srgbRed: 0x1C / 255, green: 0x1D / 255, blue: 0x20 / 255, alpha: 1)
let ink = NSColor(srgbRed: 0x2B / 255, green: 0x2D / 255, blue: 0x31 / 255, alpha: 1)

func svg(_ name: String) -> NSImage {
    guard let image = NSImage(contentsOf: brand.appendingPathComponent(name)) else { fatalError("can't load \(name)") }
    return image
}

/// Draws into a bitmap of exactly `size` pixels (no Retina scaling surprises).
func render(_ size: NSSize, to name: String, _ draw: (NSRect) -> Void) {
    guard
        let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: Int(size.width), pixelsHigh: Int(size.height), bitsPerSample: 8,
            samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0,
            bitsPerPixel: 0)
    else { fatalError() }
    rep.size = size
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    NSGraphicsContext.current?.imageInterpolation = .high
    draw(NSRect(origin: .zero, size: size))
    NSGraphicsContext.restoreGraphicsState()
    try! rep.representation(using: .png, properties: [:])!.write(to: out.appendingPathComponent(name))
    print("png/\(name)")
}

/// Fits an image into `box`, centred, keeping its aspect ratio.
func place(_ image: NSImage, in box: NSRect) {
    let s = min(box.width / image.size.width, box.height / image.size.height)
    let size = NSSize(width: image.size.width * s, height: image.size.height * s)
    image.draw(
        in: NSRect(x: box.midX - size.width / 2, y: box.midY - size.height / 2, width: size.width, height: size.height))
}

// Transparent exports.
for (file, size) in [
    ("logo-horizontal.svg", NSSize(width: 1928, height: 346)),
    ("logo-horizontal-dark.svg", NSSize(width: 1928, height: 346)),
    ("logo-stacked.svg", NSSize(width: 1458, height: 886)), ("logo-stacked-dark.svg", NSSize(width: 1458, height: 886)),
    ("logo-mark.svg", NSSize(width: 512, height: 512)), ("logo-mark-dark.svg", NSSize(width: 512, height: 512)),
] {
    let image = svg(file)
    render(size, to: file.replacingOccurrences(of: ".svg", with: ".png")) { place(image, in: $0) }
}

// Favicons: the mark with a little breathing room.
for px in [16, 32, 48] {
    let image = svg("logo-mark.svg")
    render(NSSize(width: px, height: px), to: "favicon-\(px).png") { r in
        place(image, in: r.insetBy(dx: r.width * 0.06, dy: r.width * 0.06))
    }
}

// Apple touch icon: light mark on the graphite squircle, like the app icon.
render(NSSize(width: 180, height: 180), to: "apple-touch-icon.png") { r in
    NSGradient(starting: graphiteTop, ending: graphiteBottom)!.draw(in: NSBezierPath(rect: r), angle: -90)
    place(svg("logo-mark-dark.svg"), in: r.insetBy(dx: 46, dy: 46))
}

// Social preview (Open Graph / GitHub): lockup + tagline on paper.
render(NSSize(width: 1200, height: 630), to: "og-image.png") { r in
    paper.setFill()
    r.fill()
    place(svg("logo-horizontal.svg"), in: NSRect(x: 220, y: 300, width: 760, height: 136))
    let style = NSMutableParagraphStyle()
    style.alignment = .center
    let font = NSFont(name: "Avenir Next Medium", size: 40) ?? NSFont.systemFont(ofSize: 40, weight: .medium)
    let tagline = NSAttributedString(
        string: "Every window, in its place.",
        attributes: [.font: font, .foregroundColor: ink.withAlphaComponent(0.72), .paragraphStyle: style])
    tagline.draw(in: NSRect(x: 0, y: 190, width: r.width, height: 60))
}

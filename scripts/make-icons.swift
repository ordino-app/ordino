#!/usr/bin/env swift
// Renders the ordino app icon and menu bar icon.
//
//   swift scripts/make-icons.swift                    # writes Resources/AppIcon.icns + MenuBarIcon(@2x).png
//   swift scripts/make-icons.swift --preview <dir>    # also writes preview PNGs to <dir>
//
// The mark is three uneven tiles: a tall master window plus a two-window stack.
// App icon: graphite squircle on the macOS icon grid (824 pt body on a 1024 pt canvas),
// terracotta master tile and frosted off-white stack tiles.
// Menu bar icon: monochrome template image, 18 x 18 pt (18 px and 36 px).

import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

// MARK: - Geometry

/// A rounded rect with continuous ("squircle") corners, like Apple's icon shape.
/// Each corner spans `1.528 * radius` along each edge and follows a superellipse,
/// so curvature eases in from the straight edges instead of jumping.
func continuousRect(_ rect: CGRect, radius: CGFloat) -> CGPath {
    let path = CGMutablePath()
    let span = min(radius * 1.528, min(rect.width, rect.height) / 2)
    let exponent: CGFloat = 3.8
    let steps = 48
    // Corner centers (inset by span) and the quadrant each corner sweeps, counterclockwise from the right edge.
    let corners: [(center: CGPoint, start: CGFloat)] = [
        (CGPoint(x: rect.maxX - span, y: rect.maxY - span), 0),
        (CGPoint(x: rect.minX + span, y: rect.maxY - span), .pi / 2),
        (CGPoint(x: rect.minX + span, y: rect.minY + span), .pi),
        (CGPoint(x: rect.maxX - span, y: rect.minY + span), 3 * .pi / 2),
    ]
    for (index, corner) in corners.enumerated() {
        for step in 0...steps {
            let angle = corner.start + (.pi / 2) * CGFloat(step) / CGFloat(steps)
            let cosA = cos(angle)
            let sinA = sin(angle)
            let x = corner.center.x + span * copysign(pow(abs(cosA), 2 / exponent), cosA)
            let y = corner.center.y + span * copysign(pow(abs(sinA), 2 / exponent), sinA)
            if index == 0 && step == 0 {
                path.move(to: CGPoint(x: x, y: y))
            } else {
                path.addLine(to: CGPoint(x: x, y: y))
            }
        }
    }
    path.closeSubpath()
    return path
}

func color(_ hex: UInt32, _ alpha: CGFloat = 1) -> CGColor {
    CGColor(
        srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
        green: CGFloat((hex >> 8) & 0xFF) / 255,
        blue: CGFloat(hex & 0xFF) / 255,
        alpha: alpha
    )
}

func linearGradient(_ colors: [CGColor], _ locations: [CGFloat]) -> CGGradient {
    CGGradient(
        colorsSpace: CGColorSpace(name: CGColorSpace.sRGB),
        colors: colors as CFArray,
        locations: locations
    )!
}

func makeContext(pixels: Int) -> CGContext {
    let context = CGContext(
        data: nil,
        width: pixels,
        height: pixels,
        bitsPerComponent: 8,
        bytesPerRow: 0,
        space: CGColorSpace(name: CGColorSpace.sRGB)!,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    )!
    context.interpolationQuality = .high
    context.setShouldAntialias(true)
    return context
}

func writePNG(_ image: CGImage, to url: URL) {
    guard
        let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)
    else {
        fatalError("Cannot write \(url.path)")
    }
    CGImageDestinationAddImage(destination, image, nil)
    guard CGImageDestinationFinalize(destination) else { fatalError("Cannot finalize \(url.path)") }
}

// MARK: - App icon (drawn in a 1024 x 1024 coordinate space, origin bottom left)

let terracotta: UInt32 = 0xD9653B

/// The three tiles in icon coordinates: master (left, full height), stack top, stack bottom.
func tileRects() -> (master: CGRect, top: CGRect, bottom: CGRect) {
    let inner = CGRect(x: 236, y: 236, width: 552, height: 552)
    let gap: CGFloat = 36
    let masterWidth: CGFloat = 300
    let stackX = inner.minX + masterWidth + gap
    let stackWidth = inner.maxX - stackX
    let topHeight: CGFloat = 300
    let bottomHeight = inner.height - topHeight - gap
    let master = CGRect(x: inner.minX, y: inner.minY, width: masterWidth, height: inner.height)
    let top = CGRect(x: stackX, y: inner.maxY - topHeight, width: stackWidth, height: topHeight)
    let bottom = CGRect(x: stackX, y: inner.minY, width: stackWidth, height: bottomHeight)
    return (master, top, bottom)
}

func drawAppIcon(in context: CGContext) {
    let body = CGRect(x: 100, y: 100, width: 824, height: 824)
    let bodyPath = continuousRect(body, radius: 185)

    // Drop shadow: a soft ambient one plus a tighter contact one.
    context.saveGState()
    context.setShadow(offset: CGSize(width: 0, height: -14), blur: 36, color: color(0x000000, 0.32))
    context.addPath(bodyPath)
    context.setFillColor(color(0x1C1D20))
    context.fillPath()
    context.restoreGState()
    context.saveGState()
    context.setShadow(offset: CGSize(width: 0, height: -3), blur: 6, color: color(0x000000, 0.25))
    context.addPath(bodyPath)
    context.setFillColor(color(0x1C1D20))
    context.fillPath()
    context.restoreGState()

    // Body: graphite, lighter at the top.
    context.saveGState()
    context.addPath(bodyPath)
    context.clip()
    context.drawLinearGradient(
        linearGradient([color(0x3A3C42), color(0x2B2D31), color(0x1C1D20)], [0, 0.45, 1]),
        start: CGPoint(x: 512, y: body.maxY),
        end: CGPoint(x: 512, y: body.minY),
        options: []
    )
    // Warm glow from the top left, as if lit through glass.
    context.drawRadialGradient(
        linearGradient([color(0xFFF4EA, 0.10), color(0xFFF4EA, 0)], [0, 1]),
        startCenter: CGPoint(x: 330, y: 900),
        startRadius: 0,
        endCenter: CGPoint(x: 330, y: 900),
        endRadius: 620,
        options: []
    )
    // Faint terracotta bounce under the master tile.
    context.drawRadialGradient(
        linearGradient([color(terracotta, 0.16), color(terracotta, 0)], [0, 1]),
        startCenter: CGPoint(x: 380, y: 230),
        startRadius: 0,
        endCenter: CGPoint(x: 380, y: 230),
        endRadius: 420,
        options: []
    )
    context.restoreGState()

    // Glass rim: bright at the top edge, fading out toward the bottom.
    context.saveGState()
    context.addPath(bodyPath)
    context.clip()
    context.addPath(continuousRect(body.insetBy(dx: 2, dy: 2), radius: 183))
    context.setLineWidth(4)
    context.replacePathWithStrokedPath()
    context.clip()
    context.drawLinearGradient(
        linearGradient([color(0xFFFFFF, 0.26), color(0xFFFFFF, 0.04), color(0xFFFFFF, 0.07)], [0, 0.6, 1]),
        start: CGPoint(x: 512, y: body.maxY),
        end: CGPoint(x: 512, y: body.minY),
        options: []
    )
    context.restoreGState()

    let tiles = tileRects()
    let tileRadius: CGFloat = 50

    // Tile shadows, so the tiles float slightly above the body.
    for rect in [tiles.master, tiles.top, tiles.bottom] {
        context.saveGState()
        context.setShadow(offset: CGSize(width: 0, height: -10), blur: 24, color: color(0x000000, 0.38))
        context.addPath(continuousRect(rect, radius: tileRadius))
        context.setFillColor(color(0x1C1D20))
        context.fillPath()
        context.restoreGState()
    }

    // Master tile: terracotta gradient with a glassy top sheen.
    drawTile(
        context,
        rect: tiles.master,
        radius: tileRadius,
        fill: [color(0xEC8357), color(terracotta), color(0xBF4F29)],
        sheenAlpha: 0.22,
        rimAlpha: 0.45
    )
    // Stack tiles: frosted warm off-white.
    for rect in [tiles.top, tiles.bottom] {
        drawTile(
            context,
            rect: rect,
            radius: tileRadius,
            fill: [color(0xFBF8F2, 0.96), color(0xF1ECE3, 0.92), color(0xDEDAD3, 0.88)],
            sheenAlpha: 0.35,
            rimAlpha: 0.85
        )
    }
}

func drawTile(
    _ context: CGContext,
    rect: CGRect,
    radius: CGFloat,
    fill: [CGColor],
    sheenAlpha: CGFloat,
    rimAlpha: CGFloat
) {
    let path = continuousRect(rect, radius: radius)
    context.saveGState()
    context.addPath(path)
    context.clip()
    context.drawLinearGradient(
        linearGradient(fill, [0, 0.5, 1]),
        start: CGPoint(x: rect.midX, y: rect.maxY),
        end: CGPoint(x: rect.midX, y: rect.minY),
        options: [.drawsBeforeStartLocation, .drawsAfterEndLocation]
    )
    // Sheen across the upper part.
    context.drawLinearGradient(
        linearGradient([color(0xFFFFFF, sheenAlpha), color(0xFFFFFF, 0)], [0, 1]),
        start: CGPoint(x: rect.midX, y: rect.maxY),
        end: CGPoint(x: rect.midX, y: rect.maxY - min(rect.height * 0.45, 170)),
        options: []
    )
    // Inner light stroke (1 pt at 1x would vanish on a 1024 canvas, so ~3 px here).
    context.addPath(continuousRect(rect.insetBy(dx: 1.5, dy: 1.5), radius: radius - 1.5))
    context.setLineWidth(3)
    context.replacePathWithStrokedPath()
    context.clip()
    context.drawLinearGradient(
        linearGradient([color(0xFFFFFF, rimAlpha), color(0xFFFFFF, rimAlpha * 0.25)], [0, 1]),
        start: CGPoint(x: rect.midX, y: rect.maxY),
        end: CGPoint(x: rect.midX, y: rect.minY),
        options: []
    )
    context.restoreGState()
}

func renderAppIcon(pixels: Int) -> CGImage {
    let context = makeContext(pixels: pixels)
    let scale = CGFloat(pixels) / 1024
    context.scaleBy(x: scale, y: scale)
    drawAppIcon(in: context)
    return context.makeImage()!
}

// MARK: - Menu bar icon (18 x 18 pt template, drawn in points, origin top left)

func renderMenuBarIcon(scale: Int) -> CGImage {
    let pixels = 18 * scale
    let context = makeContext(pixels: pixels)
    let s = CGFloat(scale)
    // Flip so rects below read top-down, in points.
    context.translateBy(x: 0, y: CGFloat(pixels))
    context.scaleBy(x: s, y: -s)
    context.setFillColor(color(0x000000))

    let stroke: CGFloat = 1.5
    let radius: CGFloat = 2
    // Mark spans 2...16 pt on both axes; every outer edge sits on a whole point.
    let master = CGRect(x: 2, y: 2, width: 6, height: 14)
    let top = CGRect(x: 10, y: 2, width: 6, height: 7)
    let bottom = CGRect(x: 10, y: 11, width: 6, height: 5)

    // Master: filled.
    context.addPath(continuousRect(master, radius: radius))
    context.fillPath()
    // Stack: outlined rings (outer minus inner, even-odd) so outer edges stay crisp.
    for rect in [top, bottom] {
        context.addPath(continuousRect(rect, radius: radius))
        context.addPath(continuousRect(rect.insetBy(dx: stroke, dy: stroke), radius: radius - stroke))
        context.fillPath(using: .evenOdd)
    }
    return context.makeImage()!
}

// MARK: - Main

let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
let resources = root.appendingPathComponent("Resources")
let fileManager = FileManager.default
try fileManager.createDirectory(at: resources, withIntermediateDirectories: true)

var previewDirectory: URL?
if let index = CommandLine.arguments.firstIndex(of: "--preview"), index + 1 < CommandLine.arguments.count {
    previewDirectory = URL(fileURLWithPath: CommandLine.arguments[index + 1])
}

let iconset = fileManager.temporaryDirectory.appendingPathComponent("ordino-\(UUID().uuidString).iconset")
try fileManager.createDirectory(at: iconset, withIntermediateDirectories: true)
defer { try? fileManager.removeItem(at: iconset) }

for points in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let suffix = scale == 2 ? "@2x" : ""
        let name = "icon_\(points)x\(points)\(suffix).png"
        writePNG(renderAppIcon(pixels: points * scale), to: iconset.appendingPathComponent(name))
    }
}

let icns = resources.appendingPathComponent("AppIcon.icns")
let iconutil = Process()
iconutil.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
iconutil.arguments = ["-c", "icns", iconset.path, "-o", icns.path]
try iconutil.run()
iconutil.waitUntilExit()
guard iconutil.terminationStatus == 0 else { fatalError("iconutil failed (\(iconutil.terminationStatus))") }
print("Wrote \(icns.path)")

writePNG(renderMenuBarIcon(scale: 1), to: resources.appendingPathComponent("MenuBarIcon.png"))
writePNG(renderMenuBarIcon(scale: 2), to: resources.appendingPathComponent("MenuBarIcon@2x.png"))
print("Wrote \(resources.appendingPathComponent("MenuBarIcon.png").path) (+ @2x)")

if let previewDirectory {
    try fileManager.createDirectory(at: previewDirectory, withIntermediateDirectories: true)
    for pixels in [1024, 256, 64, 32, 16] {
        writePNG(renderAppIcon(pixels: pixels), to: previewDirectory.appendingPathComponent("app-\(pixels).png"))
    }
    writePNG(renderMenuBarIcon(scale: 8), to: previewDirectory.appendingPathComponent("menubar-8x.png"))
    print("Wrote previews to \(previewDirectory.path)")
}

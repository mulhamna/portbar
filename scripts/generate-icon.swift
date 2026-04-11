#!/usr/bin/env swift
import AppKit

// Sizes required for macOS app icon
let sizes: [(Int, Int)] = [
    (16, 1), (16, 2),
    (32, 1), (32, 2),
    (128, 1), (128, 2),
    (256, 1), (256, 2),
    (512, 1), (512, 2)
]

let outputDir = CommandLine.arguments.count > 1
    ? CommandLine.arguments[1]
    : "PortBar/Resources/Assets.xcassets/AppIcon.appiconset"

func drawIcon(size: CGFloat) -> NSImage {
    let image = NSImage(size: NSSize(width: size, height: size))
    image.lockFocus()

    let ctx = NSGraphicsContext.current!.cgContext
    let rect = CGRect(x: 0, y: 0, width: size, height: size)

    // Background — dark navy rounded rect
    let radius = size * 0.22
    let bgPath = NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius)
    NSColor(red: 0.08, green: 0.10, blue: 0.18, alpha: 1).setFill()
    bgPath.fill()

    // Lightning bolt ⚡ drawn as a bezier path
    // Coordinates are in a 100x100 unit space, scaled to `size`
    let s = size / 100
    let boltPath = NSBezierPath()
    boltPath.move(to:    NSPoint(x: 58 * s, y: 84 * s))
    boltPath.line(to:    NSPoint(x: 38 * s, y: 54 * s))
    boltPath.line(to:    NSPoint(x: 52 * s, y: 54 * s))
    boltPath.line(to:    NSPoint(x: 42 * s, y: 16 * s))
    boltPath.line(to:    NSPoint(x: 63 * s, y: 50 * s))
    boltPath.line(to:    NSPoint(x: 49 * s, y: 50 * s))
    boltPath.close()

    // Gradient fill: top yellow → bottom orange
    ctx.saveGState()
    let clipPath = CGMutablePath()
    let points = [
        CGPoint(x: 58 * s, y: 84 * s),
        CGPoint(x: 38 * s, y: 54 * s),
        CGPoint(x: 52 * s, y: 54 * s),
        CGPoint(x: 42 * s, y: 16 * s),
        CGPoint(x: 63 * s, y: 50 * s),
        CGPoint(x: 49 * s, y: 50 * s),
    ]
    clipPath.addLines(between: points)
    clipPath.closeSubpath()
    ctx.addPath(clipPath)
    ctx.clip()

    let colors = [
        CGColor(red: 1.00, green: 0.90, blue: 0.20, alpha: 1),
        CGColor(red: 1.00, green: 0.55, blue: 0.05, alpha: 1),
    ] as CFArray
    let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                               colors: colors,
                               locations: [0, 1])!
    ctx.drawLinearGradient(gradient,
                           start: CGPoint(x: size / 2, y: size * 0.85),
                           end:   CGPoint(x: size / 2, y: size * 0.15),
                           options: [])
    ctx.restoreGState()

    image.unlockFocus()
    return image
}

func savePNG(_ image: NSImage, to path: String) {
    guard let tiff = image.tiffRepresentation,
          let bitmap = NSBitmapImageRep(data: tiff),
          let png = bitmap.representation(using: .png, properties: [:])
    else { return }
    try? png.write(to: URL(fileURLWithPath: path))
}

// Generate all sizes
for (points, scale) in sizes {
    let px = points * scale
    let image = drawIcon(size: CGFloat(px))
    let filename = "icon_\(points)x\(points)\(scale == 2 ? "@2x" : "").png"
    let path = "\(outputDir)/\(filename)"
    savePNG(image, to: path)
    print("Generated \(path) (\(px)x\(px)px)")
}

print("Done!")

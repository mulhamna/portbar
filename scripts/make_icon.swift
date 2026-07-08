#!/usr/bin/env swift
// Generates the PortBar app icon (indigo squircle + glowing lightning bolt).
// Zero deps — pure AppKit/CoreGraphics. Renders every AppIcon size natively.
//
// Usage: swift scripts/make_icon.swift
import AppKit

let outDir = "PortBar/Resources/Assets.xcassets/AppIcon.appiconset"

// (filename, pixel size)
let targets: [(String, Int)] = [
    ("icon_16x16.png", 16),   ("icon_16x16@2x.png", 32),
    ("icon_32x32.png", 32),   ("icon_32x32@2x.png", 64),
    ("icon_128x128.png", 128), ("icon_128x128@2x.png", 256),
    ("icon_256x256.png", 256), ("icon_256x256@2x.png", 512),
    ("icon_512x512.png", 512), ("icon_512x512@2x.png", 1024),
]

func color(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat) -> CGColor {
    CGColor(red: r/255, green: g/255, blue: b/255, alpha: 1)
}

func render(size s: Int) -> Data {
    let px = CGFloat(s)
    let cs = CGColorSpaceCreateDeviceRGB()
    let ctx = CGContext(data: nil, width: s, height: s, bitsPerComponent: 8,
                        bytesPerRow: 0, space: cs,
                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!

    // --- Squircle background with vertical indigo gradient ---
    let margin = px * 0.085
    let rect = CGRect(x: margin, y: margin, width: px - 2*margin, height: px - 2*margin)
    let radius = rect.width * 0.2237
    let squircle = CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil)

    ctx.saveGState()
    ctx.addPath(squircle)
    ctx.clip()
    let bgGrad = CGGradient(colorsSpace: cs,
        colors: [color(124, 92, 255), color(67, 56, 202), color(30, 20, 90)] as CFArray,
        locations: [0.0, 0.55, 1.0])!
    ctx.drawLinearGradient(bgGrad,
        start: CGPoint(x: rect.midX, y: rect.maxY),
        end: CGPoint(x: rect.midX, y: rect.minY), options: [])
    // subtle top sheen
    let sheen = CGGradient(colorsSpace: cs,
        colors: [CGColor(red: 1, green: 1, blue: 1, alpha: 0.18), CGColor(red: 1, green: 1, blue: 1, alpha: 0)] as CFArray,
        locations: [0.0, 1.0])!
    ctx.drawLinearGradient(sheen,
        start: CGPoint(x: rect.midX, y: rect.maxY),
        end: CGPoint(x: rect.midX, y: rect.midY), options: [])
    ctx.restoreGState()

    // --- Lightning bolt (unit coords, y-up), centered ---
    let bolt: [CGPoint] = [
        CGPoint(x: 0.60, y: 0.98),
        CGPoint(x: 0.24, y: 0.46),
        CGPoint(x: 0.46, y: 0.46),
        CGPoint(x: 0.38, y: 0.02),
        CGPoint(x: 0.78, y: 0.58),
        CGPoint(x: 0.55, y: 0.58),
    ]
    let boltSize = px * 0.46
    let ox = (px - boltSize) / 2
    let oy = (px - boltSize) / 2
    let path = CGMutablePath()
    for (i, p) in bolt.enumerated() {
        let pt = CGPoint(x: ox + p.x * boltSize, y: oy + p.y * boltSize)
        if i == 0 { path.move(to: pt) } else { path.addLine(to: pt) }
    }
    path.closeSubpath()

    // glow
    ctx.saveGState()
    ctx.setShadow(offset: .zero, blur: px * 0.05, color: color(253, 224, 71).copy(alpha: 0.9))
    ctx.addPath(path)
    ctx.setFillColor(color(253, 224, 71))
    ctx.fillPath()
    ctx.restoreGState()

    // bolt with yellow→orange gradient
    ctx.saveGState()
    ctx.addPath(path)
    ctx.clip()
    let boltGrad = CGGradient(colorsSpace: cs,
        colors: [color(255, 240, 150), color(253, 224, 71), color(251, 146, 60)] as CFArray,
        locations: [0.0, 0.5, 1.0])!
    ctx.drawLinearGradient(boltGrad,
        start: CGPoint(x: px/2, y: oy + boltSize),
        end: CGPoint(x: px/2, y: oy), options: [])
    ctx.restoreGState()

    let img = ctx.makeImage()!
    let rep = NSBitmapImageRep(cgImage: img)
    return rep.representation(using: .png, properties: [:])!
}

for (name, s) in targets {
    let data = render(size: s)
    let url = URL(fileURLWithPath: "\(outDir)/\(name)")
    try! data.write(to: url)
    print("✓ \(name) (\(s)px)")
}
print("done")

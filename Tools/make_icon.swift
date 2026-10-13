import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

// 32x32 pixel-art RetroPaint icon, rendered at 1024 for iOS and as a rounded tile for macOS.
typealias RGB = (UInt8, UInt8, UInt8)
let N = 32
var art = [[RGB?]](repeating: [RGB?](repeating: nil, count: N), count: N)
func set(_ x: Int, _ y: Int, _ c: RGB) { if x >= 0 && y >= 0 && x < N && y < N { art[y][x] = c } }

let black: RGB = (0, 0, 0)

/// Draws a stick (brush or pencil) from `a` (bottom, inside the cup) to `b` (top), then outlines it.
/// `shape` gives the half-width and colour at distance `u` along the stick.
func stick(from a: (x: Double, y: Double), to b: (x: Double, y: Double),
           _ shape: (_ u: Double, _ len: Double, _ v: Double) -> RGB?, halfWidth: (_ u: Double, _ len: Double) -> Double) {
    let len = hypot(b.x - a.x, b.y - a.y), dx = (b.x - a.x) / len, dy = (b.y - a.y) / len
    var mine = Set<Int>()
    for y in 0..<N { for x in 0..<N {
        let px = Double(x) + 0.5 - a.x, py = Double(y) + 0.5 - a.y
        let u = px * dx + py * dy, v = abs(px * dy - py * dx)
        guard u >= 0, u <= len, v <= halfWidth(u, len), let c = shape(u, len, v) else { continue }
        set(x, y, c); mine.insert(y * N + x)
    }}
    for p in mine {
        let x = p % N, y = p / N
        for (ox, oy) in [(-1, 0), (1, 0), (0, -1), (0, 1)] where !mine.contains((y + oy) * N + x + ox) {
            set(x + ox, y + oy, black)
        }
    }
}

/// A paintbrush: wooden handle, metal ferrule, bristles dipped in `paint`.
func brush(from a: (x: Double, y: Double), to b: (x: Double, y: Double), handle: RGB, paint: RGB) {
    stick(from: a, to: b, { u, len, v in
        if u < len - 8 { return v < 0.5 ? handle : (handle.0 / 4 * 3, handle.1 / 4 * 3, handle.2 / 4 * 3) }
        if u < len - 6 { return (200, 200, 210) }
        if u < len - 3.5 { return (90, 60, 40) }
        return paint
    }, halfWidth: { u, len in
        if u < len - 8 { return 1.1 }
        if u < len - 6 { return 1.5 }
        if u < len - 2 { return 1.9 }
        return 1.9 * max(0.25, (len - u) / 2)
    })
}

// Behind the cup: two brushes and a pencil, fanned out.
brush(from: (14.5, 25), to: (4.5, 3.5), handle: (200, 40, 40), paint: (30, 90, 230))
brush(from: (16.5, 25), to: (15.0, 1.5), handle: (150, 95, 50), paint: (40, 180, 40))
stick(from: (18.5, 25), to: (27.5, 4.0), { u, len, v in
    if u < len - 5 { return v < 0.6 ? (255, 225, 70) : (240, 175, 20) }
    if u < len - 1.8 { return (235, 200, 150) }
    return (40, 40, 40)
}, halfWidth: { u, len in u < len - 5 ? 1.7 : 1.7 * (len - u) / 5 })

// The glass cup: everything behind it shows through, tinted.
func blend(_ a: RGB, _ b: RGB, _ t: Double) -> RGB {
    (UInt8(Double(a.0) * (1 - t) + Double(b.0) * t), UInt8(Double(a.1) * (1 - t) + Double(b.1) * t),
     UInt8(Double(a.2) * (1 - t) + Double(b.2) * t))
}
let glass: RGB = (175, 215, 240)
for y in 16...29 {
    let inset = y >= 27 ? 1 : 0  // the base narrows slightly
    for x in (8 + inset)...(23 - inset) {
        let edge = y == 16 || y == 29 || x == 8 + inset || x == 23 - inset
        if edge { set(x, y, black); continue }
        let under = art[y][x] ?? (235, 245, 255)
        // Outlines fade most behind the glass, so the sticks read as soft colour.
        var c = blend(under, glass, under == black ? 0.8 : 0.4)
        if x == 10 + inset || x == 11 + inset { c = blend(c, (255, 255, 255), 0.6) }  // highlight
        if y == 17 { c = (225, 240, 255) }  // rim
        set(x, y, c)
    }
}
// Red paint dripping over the rim.
for (x, h) in [(17, 3), (18, 5), (19, 4), (20, 2)] { for y in 17...(17 + h) { set(x, y, (215, 35, 35)) } }
set(18, 23, (215, 35, 35))

let space = CGColorSpace(name: CGColorSpace.sRGB)!
func context(_ s: Int) -> CGContext {
    CGContext(data: nil, width: s, height: s, bitsPerComponent: 8, bytesPerRow: 0, space: space,
              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
}
func sky(_ ctx: CGContext, _ rect: CGRect) {
    let g = CGGradient(colorsSpace: space, colors: [CGColor(srgbRed: 0.35, green: 0.62, blue: 1, alpha: 1),
                                                    CGColor(srgbRed: 0.02, green: 0.30, blue: 0.85, alpha: 1)] as CFArray,
                       locations: [0, 1])!
    ctx.drawLinearGradient(g, start: CGPoint(x: rect.midX, y: rect.maxY), end: CGPoint(x: rect.midX, y: rect.minY), options: [])
}
func drawArt(_ ctx: CGContext, origin: CGPoint, cell: CGFloat, total: CGFloat) {
    for y in 0..<N { for x in 0..<N {
        guard let c = art[y][x] else { continue }
        ctx.setFillColor(CGColor(srgbRed: CGFloat(c.0) / 255, green: CGFloat(c.1) / 255, blue: CGFloat(c.2) / 255, alpha: 1))
        ctx.fill(CGRect(x: origin.x + CGFloat(x) * cell, y: origin.y + total - CGFloat(y + 1) * cell, width: cell, height: cell))
    }}
}
func save(_ ctx: CGContext, _ path: String) {
    let dest = CGImageDestinationCreateWithURL(URL(fileURLWithPath: path) as CFURL, UTType.png.identifier as CFString, 1, nil)!
    CGImageDestinationAddImage(dest, ctx.makeImage()!, nil)
    CGImageDestinationFinalize(dest)
}

// Usage: swift Tools/make_icon.swift <output-dir>
let out = CommandLine.arguments[1]

// iOS: full-bleed square; the system applies the mask.
let ios = context(1024)
ios.interpolationQuality = .none
sky(ios, CGRect(x: 0, y: 0, width: 1024, height: 1024))
drawArt(ios, origin: .zero, cell: 32, total: 1024)
save(ios, "\(out)/icon-ios-1024.png")

// macOS: rounded tile inset per the macOS icon grid, with a soft shadow.
let mac = context(1024)
let tile = CGRect(x: 100, y: 100, width: 824, height: 824)
let shape = CGPath(roundedRect: tile, cornerWidth: 185, cornerHeight: 185, transform: nil)
mac.saveGState()
mac.setShadow(offset: CGSize(width: 0, height: -10), blur: 24, color: CGColor(gray: 0, alpha: 0.35))
mac.addPath(shape); mac.setFillColor(CGColor(gray: 1, alpha: 1)); mac.fillPath()
mac.restoreGState()
mac.saveGState()
mac.addPath(shape); mac.clip()
sky(mac, tile)
drawArt(mac, origin: CGPoint(x: 96, y: 96), cell: 26, total: 832)
mac.restoreGState()
save(mac, "\(out)/icon-mac-1024.png")

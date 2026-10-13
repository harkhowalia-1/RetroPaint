import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

// 32x32 pixel-art RetroPaint icon, rendered at 1024 for iOS and as a rounded tile for macOS.
typealias RGB = (UInt8, UInt8, UInt8)
let N = 32
var art = [[RGB?]](repeating: [RGB?](repeating: nil, count: N), count: N)
func set(_ x: Int, _ y: Int, _ c: RGB) { if x >= 0 && y >= 0 && x < N && y < N { art[y][x] = c } }

let black: RGB = (0, 0, 0), white: RGB = (255, 255, 255), shadow: RGB = (22, 52, 140)

// Paper with drop shadow and outline.
for y in 6...27 { for x in 7...24 { set(x, y, shadow) } }
for y in 5...26 { for x in 6...23 { set(x, y, (y == 5 || y == 26 || x == 6 || x == 23) ? black : white) } }

// Rainbow arc on the paper.
let rings: [RGB] = [(230, 30, 30), (255, 140, 0), (255, 220, 0), (40, 180, 40), (30, 90, 230), (120, 40, 200)]
for y in 8...21 { for x in 7...22 {
    let d = hypot(Double(x) + 0.5 - 13.0, Double(y) + 0.5 - 22.0)
    let i = Int(10.5 - d)
    if i >= 0 && i < rings.count && Double(y) < 21 { set(x, y, rings[i]) }
}}

// Pencil lying diagonally across the corner, tip touching the paper.
let a = (x: 28.5, y: 9.0), b = (x: 16.0, y: 21.5)
let len = hypot(b.x - a.x, b.y - a.y), dx = (b.x - a.x) / len, dy = (b.y - a.y) / len
var pencil = Set<Int>()
for y in 0..<N { for x in 0..<N {
    let px = Double(x) + 0.5 - a.x, py = Double(y) + 0.5 - a.y
    let u = px * dx + py * dy, v = abs(px * dy - py * dx)
    guard u >= 0 && u <= len else { continue }
    let coneStart = len - 4.5
    let halfWidth = u < coneStart ? 1.9 : 1.9 * (len - u) / 4.5
    guard v <= halfWidth else { continue }
    let c: RGB
    if u < 2.5 { c = (240, 150, 160) }
    else if u < 4 { c = (190, 190, 200) }
    else if u < coneStart { c = v < 0.7 ? (255, 225, 70) : (240, 180, 20) }
    else if u < len - 1.6 { c = (235, 200, 150) }
    else { c = (40, 40, 40) }
    set(x, y, c); pencil.insert(y * N + x)
}}
for p in pencil {
    let x = p % N, y = p / N
    for (ox, oy) in [(-1, 0), (1, 0), (0, -1), (0, 1)] where !pencil.contains((y + oy) * N + x + ox) {
        set(x + ox, y + oy, black)
    }
}

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

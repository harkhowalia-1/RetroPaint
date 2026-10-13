import CoreGraphics
import CoreText
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// One pixel, stored as RGBA bytes in memory (little-endian `UInt32`).
typealias Pixel = UInt32

struct RGBA: Hashable {
    var r: UInt8
    var g: UInt8
    var b: UInt8

    init(_ r: UInt8, _ g: UInt8, _ b: UInt8) {
        self.r = r; self.g = g; self.b = b
    }

    init(hex: UInt32) {
        self.init(UInt8((hex >> 16) & 0xFF), UInt8((hex >> 8) & 0xFF), UInt8(hex & 0xFF))
    }

    init(pixel: Pixel) {
        self.init(UInt8(pixel & 0xFF), UInt8((pixel >> 8) & 0xFF), UInt8((pixel >> 16) & 0xFF))
    }

    init?(cgColor: CGColor) {
        guard let c = cgColor.converted(to: Bitmap.colorSpace, intent: .defaultIntent, options: nil),
              let comps = c.components, comps.count >= 3 else { return nil }
        func byte(_ v: CGFloat) -> UInt8 { UInt8(max(0, min(255, (v * 255).rounded()))) }
        self.init(byte(comps[0]), byte(comps[1]), byte(comps[2]))
    }

    var pixel: Pixel { Pixel(r) | Pixel(g) << 8 | Pixel(b) << 16 | 0xFF00_0000 }
    var cgColor: CGColor {
        CGColor(srgbRed: CGFloat(r) / 255, green: CGFloat(g) / 255, blue: CGFloat(b) / 255, alpha: 1)
    }
    var inverted: RGBA { RGBA(255 - r, 255 - g, 255 - b) }

    static let black = RGBA(0, 0, 0)
    static let white = RGBA(255, 255, 255)
}

struct IntPoint: Hashable {
    var x: Int
    var y: Int
    init(_ x: Int, _ y: Int) { self.x = x; self.y = y }
    static let zero = IntPoint(0, 0)
    static func + (a: IntPoint, b: IntPoint) -> IntPoint { IntPoint(a.x + b.x, a.y + b.y) }
    static func - (a: IntPoint, b: IntPoint) -> IntPoint { IntPoint(a.x - b.x, a.y - b.y) }
}

struct IntSize: Hashable {
    var width: Int
    var height: Int
}

struct IntRect: Hashable {
    var x: Int
    var y: Int
    var width: Int
    var height: Int

    init(x: Int, y: Int, width: Int, height: Int) {
        self.x = x; self.y = y; self.width = width; self.height = height
    }

    /// The rectangle spanning both corner pixels, inclusive.
    init(corner a: IntPoint, _ b: IntPoint) {
        x = min(a.x, b.x); y = min(a.y, b.y)
        width = abs(a.x - b.x) + 1; height = abs(a.y - b.y) + 1
    }

    var origin: IntPoint { IntPoint(x, y) }
    var maxX: Int { x + width }
    var maxY: Int { y + height }
    var isEmpty: Bool { width <= 0 || height <= 0 }

    func contains(_ p: IntPoint) -> Bool { p.x >= x && p.x < maxX && p.y >= y && p.y < maxY }

    func intersection(_ o: IntRect) -> IntRect {
        let nx = max(x, o.x), ny = max(y, o.y)
        return IntRect(x: nx, y: ny, width: max(0, min(maxX, o.maxX) - nx), height: max(0, min(maxY, o.maxY) - ny))
    }
}

/// An opaque, aliased raster image. All of Paint's drawing is pixel-exact, so
/// every primitive here works on whole pixels with no anti-aliasing.
struct Bitmap: Equatable {
    private(set) var width: Int
    private(set) var height: Int
    var pixels: [Pixel]

    static let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!
    private static let bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue

    init(width: Int, height: Int, fill: Pixel = RGBA.white.pixel) {
        self.width = max(1, width)
        self.height = max(1, height)
        pixels = Array(repeating: fill, count: self.width * self.height)
    }

    var bounds: IntRect { IntRect(x: 0, y: 0, width: width, height: height) }
    var size: IntSize { IntSize(width: width, height: height) }

    @inline(__always) func contains(_ x: Int, _ y: Int) -> Bool {
        x >= 0 && y >= 0 && x < width && y < height
    }

    @inline(__always) func pixel(_ x: Int, _ y: Int) -> Pixel { pixels[y * width + x] }

    @inline(__always) mutating func set(_ x: Int, _ y: Int, _ c: Pixel) {
        if contains(x, y) { pixels[y * width + x] = c }
    }

    mutating func fill(_ rect: IntRect, _ c: Pixel) {
        let r = rect.intersection(bounds)
        guard !r.isEmpty else { return }
        for y in r.y..<r.maxY {
            let row = y * width
            for x in r.x..<r.maxX { pixels[row + x] = c }
        }
    }

    // MARK: Lines and pens

    static func forEachLinePoint(_ a: IntPoint, _ b: IntPoint, _ body: (Int, Int) -> Void) {
        var x = a.x, y = a.y
        let dx = abs(b.x - a.x), dy = -abs(b.y - a.y)
        let sx = a.x < b.x ? 1 : -1, sy = a.y < b.y ? 1 : -1
        var err = dx + dy
        while true {
            body(x, y)
            if x == b.x && y == b.y { break }
            let e2 = 2 * err
            if e2 >= dy { err += dy; x += sx }
            if e2 <= dx { err += dx; y += sy }
        }
    }

    /// A round pen `width` pixels across.
    static func penOffsets(width: Int) -> [IntPoint] {
        guard width > 1 else { return [.zero] }
        let c = Double(width - 1) / 2, r2 = Double(width * width) / 4
        var out: [IntPoint] = []
        for dy in 0..<width {
            for dx in 0..<width {
                let fx = Double(dx) - c, fy = Double(dy) - c
                if fx * fx + fy * fy <= r2 { out.append(IntPoint(dx - (width - 1) / 2, dy - (width - 1) / 2)) }
            }
        }
        return out
    }

    static func squareOffsets(_ size: Int) -> [IntPoint] {
        var out: [IntPoint] = []
        for dy in 0..<size { for dx in 0..<size { out.append(IntPoint(dx - size / 2, dy - size / 2)) } }
        return out
    }

    mutating func stamp(_ offsets: [IntPoint], at x: Int, _ y: Int, _ c: Pixel) {
        for o in offsets { set(x + o.x, y + o.y, c) }
    }

    mutating func drawLine(_ a: IntPoint, _ b: IntPoint, offsets: [IntPoint], color c: Pixel) {
        Bitmap.forEachLinePoint(a, b) { x, y in stamp(offsets, at: x, y, c) }
    }

    // MARK: Shapes

    enum ShapeKind { case rectangle, ellipse, roundedRectangle }

    private static func shapeContains(_ kind: ShapeKind, _ r: IntRect, inset: Int, _ x: Int, _ y: Int) -> Bool {
        let w = Double(r.width - 2 * inset), h = Double(r.height - 2 * inset)
        guard w > 0, h > 0 else { return false }
        let px = Double(x - r.x - inset) + 0.5, py = Double(y - r.y - inset) + 0.5
        guard px >= 0, py >= 0, px <= w, py <= h else { return false }
        switch kind {
        case .rectangle:
            return true
        case .ellipse:
            let dx = (px - w / 2) / (w / 2), dy = (py - h / 2) / (h / 2)
            return dx * dx + dy * dy <= 1.0001
        case .roundedRectangle:
            let rad = max(0, min(8.0 - Double(inset), w / 2, h / 2))
            let cx = min(max(px, rad), w - rad), cy = min(max(py, rad), h - rad)
            let dx = px - cx, dy = py - cy
            return dx * dx + dy * dy <= rad * rad + 0.0001
        }
    }

    mutating func drawShape(_ kind: ShapeKind, in r: IntRect, lineWidth: Int, stroke: Pixel?, fill fillColor: Pixel?) {
        let clip = r.intersection(bounds)
        guard !clip.isEmpty else { return }
        for y in clip.y..<clip.maxY {
            for x in clip.x..<clip.maxX {
                guard Bitmap.shapeContains(kind, r, inset: 0, x, y) else { continue }
                if let s = stroke, !Bitmap.shapeContains(kind, r, inset: lineWidth, x, y) {
                    pixels[y * width + x] = s
                } else if let f = fillColor {
                    pixels[y * width + x] = f
                }
            }
        }
    }

    /// Calls `body` for each pixel inside the polygon (even-odd rule, pixel centres).
    static func forEachPolygonPixel(_ pts: [IntPoint], clip: IntRect, _ body: (Int, Int) -> Void) {
        guard pts.count >= 3, let lo = pts.map(\.y).min(), let hi = pts.map(\.y).max() else { return }
        let minY = max(clip.y, lo), maxY = min(clip.maxY - 1, hi)
        guard minY <= maxY else { return }
        var xs: [Double] = []
        for y in minY...maxY {
            xs.removeAll(keepingCapacity: true)
            let sy = Double(y)
            var j = pts.count - 1
            for i in 0..<pts.count {
                let a = pts[i], b = pts[j]
                j = i
                let ay = Double(a.y), by = Double(b.y)
                if (ay <= sy && by > sy) || (by <= sy && ay > sy) {
                    xs.append(Double(a.x) + (sy - ay) / (by - ay) * Double(b.x - a.x))
                }
            }
            xs.sort()
            var k = 0
            while k + 1 < xs.count {
                let x0 = max(clip.x, Int(xs[k].rounded(.up)))
                let x1 = min(clip.maxX - 1, Int(xs[k + 1].rounded(.down)))
                if x0 <= x1 { for x in x0...x1 { body(x, y) } }
                k += 2
            }
        }
    }

    mutating func drawPolygon(_ pts: [IntPoint], lineWidth: Int, stroke: Pixel?, fill fillColor: Pixel?) {
        guard !pts.isEmpty else { return }
        if let f = fillColor {
            let w = width
            Bitmap.forEachPolygonPixel(pts, clip: bounds) { x, y in pixels[y * w + x] = f }
        }
        let edge = stroke ?? fillColor
        guard let edgeColor = edge else { return }
        let pen = stroke == nil ? [IntPoint.zero] : Bitmap.penOffsets(width: lineWidth)
        for i in pts.indices { drawLine(pts[i], pts[(i + 1) % pts.count], offsets: pen, color: edgeColor) }
    }

    // MARK: Fill

    mutating func floodFill(from x: Int, _ y: Int, with c: Pixel) {
        guard contains(x, y) else { return }
        let target = pixel(x, y)
        guard target != c else { return }
        var stack = [IntPoint(x, y)]
        while let p = stack.popLast() {
            let row = p.y * width
            guard pixels[row + p.x] == target else { continue }
            var lx = p.x, rx = p.x
            while lx > 0 && pixels[row + lx - 1] == target { lx -= 1 }
            while rx < width - 1 && pixels[row + rx + 1] == target { rx += 1 }
            for i in lx...rx { pixels[row + i] = c }
            for ny in [p.y - 1, p.y + 1] where ny >= 0 && ny < height {
                let nrow = ny * width
                var i = lx
                while i <= rx {
                    if pixels[nrow + i] == target {
                        stack.append(IntPoint(i, ny))
                        while i <= rx && pixels[nrow + i] == target { i += 1 }
                    } else {
                        i += 1
                    }
                }
            }
        }
    }

    // MARK: Transforms

    func cropped(to rect: IntRect, fill: Pixel) -> Bitmap {
        var out = Bitmap(width: rect.width, height: rect.height, fill: fill)
        for y in 0..<out.height {
            for x in 0..<out.width where contains(rect.x + x, rect.y + y) {
                out.pixels[y * out.width + x] = pixel(rect.x + x, rect.y + y)
            }
        }
        return out
    }

    func resizedCanvas(width w: Int, height h: Int, fill: Pixel) -> Bitmap {
        cropped(to: IntRect(x: 0, y: 0, width: max(1, w), height: max(1, h)), fill: fill)
    }

    func flippedHorizontally() -> Bitmap {
        var o = self
        for y in 0..<height { for x in 0..<width { o.pixels[y * width + x] = pixel(width - 1 - x, y) } }
        return o
    }

    func flippedVertically() -> Bitmap {
        var o = self
        for y in 0..<height { for x in 0..<width { o.pixels[y * width + x] = pixel(x, height - 1 - y) } }
        return o
    }

    /// Rotates clockwise by `quarterTurns` × 90°.
    func rotated(quarterTurns: Int) -> Bitmap {
        let t = ((quarterTurns % 4) + 4) % 4
        if t == 0 { return self }
        if t == 2 { var o = self; o.pixels.reverse(); return o }
        var o = Bitmap(width: height, height: width)
        for y in 0..<height {
            for x in 0..<width {
                let c = pixel(x, y)
                if t == 1 { o.pixels[x * o.width + (height - 1 - y)] = c }
                else { o.pixels[(width - 1 - x) * o.width + y] = c }
            }
        }
        return o
    }

    func scaled(toWidth w: Int, height h: Int) -> Bitmap {
        var o = Bitmap(width: w, height: h)
        for y in 0..<o.height {
            let sy = min(height - 1, y * height / o.height)
            for x in 0..<o.width {
                o.pixels[y * o.width + x] = pixel(min(width - 1, x * width / o.width), sy)
            }
        }
        return o
    }

    func skewed(horizontalDegrees: Double, verticalDegrees: Double, fill: Pixel) -> Bitmap {
        var src = self
        if horizontalDegrees != 0 {
            let t = tan(horizontalDegrees * .pi / 180)
            let extra = Int((abs(t) * Double(src.height)).rounded(.up))
            var o = Bitmap(width: src.width + extra, height: src.height, fill: fill)
            for y in 0..<src.height {
                let off = Int((Double(y) * t).rounded()) + (t < 0 ? extra : 0)
                for x in 0..<src.width { o.set(x + off, y, src.pixel(x, y)) }
            }
            src = o
        }
        if verticalDegrees != 0 {
            let t = tan(verticalDegrees * .pi / 180)
            let extra = Int((abs(t) * Double(src.width)).rounded(.up))
            var o = Bitmap(width: src.width, height: src.height + extra, fill: fill)
            for x in 0..<src.width {
                let off = Int((Double(x) * t).rounded()) + (t < 0 ? extra : 0)
                for y in 0..<src.height { o.set(x, y + off, src.pixel(x, y)) }
            }
            src = o
        }
        return src
    }

    func inverted() -> Bitmap {
        var o = self
        for i in o.pixels.indices { o.pixels[i] ^= 0x00FF_FFFF }
        return o
    }

    /// Copies `other` onto this bitmap. Pixels matching `key`, or where `mask` is 0, are skipped.
    mutating func draw(_ other: Bitmap, at origin: IntPoint, transparent key: Pixel? = nil, mask: Bitmap? = nil) {
        for y in 0..<other.height {
            let dy = origin.y + y
            guard dy >= 0 && dy < height else { continue }
            for x in 0..<other.width {
                let dx = origin.x + x
                guard dx >= 0 && dx < width else { continue }
                let i = y * other.width + x
                if let mask, mask.pixels[i] == 0 { continue }
                let c = other.pixels[i]
                if c == key { continue }
                pixels[dy * width + dx] = c
            }
        }
    }

    // MARK: Text

    mutating func drawText(_ text: String, in rect: IntRect, font: CTFont, underline: Bool, color: RGBA) {
        let w = width, h = height
        pixels.withUnsafeMutableBytes { buf in
            guard let ctx = CGContext(data: buf.baseAddress, width: w, height: h, bitsPerComponent: 8,
                                      bytesPerRow: w * 4, space: Bitmap.colorSpace, bitmapInfo: Bitmap.bitmapInfo)
            else { return }
            ctx.setAllowsAntialiasing(false)
            ctx.setShouldAntialias(false)
            ctx.setAllowsFontSmoothing(false)
            ctx.setShouldSmoothFonts(false)
            var attrs: [NSAttributedString.Key: Any] = [
                NSAttributedString.Key(kCTFontAttributeName as String): font,
                NSAttributedString.Key(kCTForegroundColorAttributeName as String): color.cgColor,
            ]
            if underline {
                attrs[NSAttributedString.Key(kCTUnderlineStyleAttributeName as String)] =
                    NSNumber(value: CTUnderlineStyle.single.rawValue)
            }
            let setter = CTFramesetterCreateWithAttributedString(NSAttributedString(string: text, attributes: attrs))
            let box = CGRect(x: rect.x, y: h - rect.y - rect.height, width: rect.width, height: rect.height)
            let frame = CTFramesetterCreateFrame(setter, CFRange(location: 0, length: 0), CGPath(rect: box, transform: nil), nil)
            ctx.clip(to: box)
            CTFrameDraw(frame, ctx)
        }
    }

    // MARK: Conversion

    /// Pixels equal to `key`, or where `mask` is 0, become transparent.
    func makeCGImage(transparent key: Pixel? = nil, mask: Bitmap? = nil) -> CGImage? {
        var data = pixels
        if key != nil || mask != nil {
            for i in data.indices where data[i] == key || mask?.pixels[i] == 0 { data[i] = 0 }
        }
        guard let provider = CGDataProvider(data: data.withUnsafeBytes { Data($0) } as CFData) else { return nil }
        return CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: width * 4,
                       space: Bitmap.colorSpace, bitmapInfo: CGBitmapInfo(rawValue: Bitmap.bitmapInfo),
                       provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)
    }

    /// Flattens any transparency onto white, as Paint does.
    init?(cgImage: CGImage) {
        self.init(width: cgImage.width, height: cgImage.height)
        let w = width, h = height
        let ok = pixels.withUnsafeMutableBytes { buf -> Bool in
            guard let ctx = CGContext(data: buf.baseAddress, width: w, height: h, bitsPerComponent: 8,
                                      bytesPerRow: w * 4, space: Bitmap.colorSpace, bitmapInfo: Bitmap.bitmapInfo)
            else { return false }
            ctx.interpolationQuality = .none
            ctx.draw(cgImage, in: CGRect(x: 0, y: 0, width: w, height: h))
            return true
        }
        guard ok else { return nil }
        for i in pixels.indices { pixels[i] |= 0xFF00_0000 }
    }

    init?(data: Data) {
        guard let src = CGImageSourceCreateWithData(data as CFData, nil),
              let img = CGImageSourceCreateImageAtIndex(src, 0, nil) else { return nil }
        self.init(cgImage: img)
    }

    func encoded(as type: UTType) -> Data? {
        guard let img = makeCGImage() else { return nil }
        let data = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(data as CFMutableData, type.identifier as CFString, 1, nil)
        else { return nil }
        CGImageDestinationAddImage(dest, img, [kCGImageDestinationLossyCompressionQuality: 0.95] as CFDictionary)
        guard CGImageDestinationFinalize(dest) else { return nil }
        return data as Data
    }
}

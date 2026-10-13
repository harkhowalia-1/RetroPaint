import CoreGraphics

/// Original 16×16 pixel-art icons in the classic toolbox style.
@MainActor
enum ToolIcons {
    private static var cache: [Tool: CGImage] = [:]

    static func image(for tool: Tool) -> CGImage? {
        if let c = cache[tool] { return c }
        let img = bitmap(for: tool).makeCGImage()
        cache[tool] = img
        return img
    }

    private static let colors: [Character: Pixel] = [
        "k": RGBA.black.pixel,
        "w": RGBA.white.pixel,
        "g": RGBA(hex: 0x808080).pixel,
        "s": RGBA(hex: 0xC0C0C0).pixel,
        "y": RGBA(hex: 0xFFE060).pixel,
        "p": RGBA(hex: 0xF0A0A0).pixel,
        "t": RGBA(hex: 0xE0C090).pixel,
        "o": RGBA(hex: 0x9C5A28).pixel,
        "b": RGBA(hex: 0x2050D0).pixel,
        "c": RGBA(hex: 0xA0E0FF).pixel,
        "r": RGBA(hex: 0xD02020).pixel,
    ]

    private static func fromMap(_ rows: [String]) -> Bitmap {
        var b = Bitmap(width: 16, height: 16, fill: 0)
        for (y, row) in rows.enumerated() {
            for (x, ch) in row.enumerated() { if let c = colors[ch] { b.set(x, y, c) } }
        }
        return b
    }

    /// Keeps every other pair of pixels, for marching-ants outlines.
    private static func dashed(_ b: Bitmap) -> Bitmap {
        var o = b
        for y in 0..<16 { for x in 0..<16 where (x + y) % 4 >= 2 { o.set(x, y, 0) } }
        return o
    }

    private static func bitmap(for tool: Tool) -> Bitmap {
        let k = RGBA.black.pixel
        var b = Bitmap(width: 16, height: 16, fill: 0)
        switch tool {
        case .freeSelect:
            let pts = [IntPoint(7, 1), IntPoint(10, 4), IntPoint(14, 5), IntPoint(11, 9), IntPoint(13, 14),
                       IntPoint(7, 11), IntPoint(2, 14), IntPoint(4, 8), IntPoint(1, 5), IntPoint(5, 4)]
            b.drawPolygon(pts, lineWidth: 1, stroke: k, fill: nil)
            return dashed(b)
        case .rectSelect:
            b.drawShape(.rectangle, in: IntRect(x: 1, y: 2, width: 14, height: 12), lineWidth: 1, stroke: k, fill: nil)
            return dashed(b)
        case .line:
            b.drawLine(IntPoint(2, 13), IntPoint(13, 2), offsets: [.zero], color: k)
        case .curve:
            var prev = IntPoint(1, 13)
            for i in 1...24 {
                let t = Double(i) / 24, u = 1 - t
                let x = u * u * u * 1 + 3 * u * u * t * 4 + 3 * u * t * t * 11 + t * t * t * 14
                let y = u * u * u * 13 + 3 * u * u * t * -6 + 3 * u * t * t * 22 + t * t * t * 2
                let p = IntPoint(Int(x.rounded()), Int(y.rounded()))
                b.drawLine(prev, p, offsets: [.zero], color: k)
                prev = p
            }
        case .rectangle:
            b.drawShape(.rectangle, in: IntRect(x: 1, y: 3, width: 14, height: 10), lineWidth: 1, stroke: k, fill: RGBA(hex: 0x808080).pixel)
        case .polygon:
            let pts = [IntPoint(1, 13), IntPoint(4, 2), IntPoint(8, 7), IntPoint(14, 2), IntPoint(12, 13)]
            b.drawPolygon(pts, lineWidth: 1, stroke: k, fill: RGBA(hex: 0x808080).pixel)
        case .ellipse:
            b.drawShape(.ellipse, in: IntRect(x: 1, y: 3, width: 14, height: 10), lineWidth: 1, stroke: k, fill: RGBA(hex: 0x808080).pixel)
        case .roundedRectangle:
            b.drawShape(.roundedRectangle, in: IntRect(x: 1, y: 3, width: 14, height: 10), lineWidth: 1, stroke: k, fill: RGBA(hex: 0x808080).pixel)
        case .pencil:
            return fromMap([
                "................",
                ".............kk.",
                "...........kppk.",
                "..........kppk..",
                ".........kssk...",
                "........kyyk....",
                ".......kyyk.....",
                "......kyyk......",
                ".....kyyk.......",
                "....kyyk........",
                "...kyyk.........",
                "..kttk..........",
                "..ktk...........",
                ".kk.............",
                "................",
                "................",
            ])
        case .brush:
            return fromMap([
                "................",
                ".............oo.",
                "............oo..",
                "...........oo...",
                "..........oo....",
                ".........oo.....",
                "........oo......",
                "......ssss......",
                ".....ssss.......",
                "....kkkk........",
                "...kkkk.........",
                "..kkkk..........",
                "..kkk...........",
                "..kk............",
                "..k.............",
                "................",
            ])
        case .eraser:
            return fromMap([
                "................",
                "................",
                "........kkkkkkk.",
                ".......kwwwwwwkk",
                "......kwwwwwwkgk",
                ".....kwwwwwwkggk",
                "....kwwwwwwkgggk",
                "...kkkkkkkkggggk",
                "...kppppppkgggk.",
                "...kppppppkggk..",
                "...kppppppkgk...",
                "...kppppppkk....",
                "...kkkkkkkk.....",
                "................",
                "................",
                "................",
            ])
        case .fill:
            return fromMap([
                "................",
                "......kk........",
                ".....kssk.......",
                "....kswssk......",
                "...kswwwssk.....",
                "..kswwwwwssk....",
                ".kswwwwwwwssk...",
                "ksswwwwwwwwsk...",
                ".ksssswwwwwsk.bb",
                "..ksssswwsk...bb",
                "...kssssk.....bb",
                "....kssk......bb",
                ".....kk.......b.",
                "..............b.",
                "................",
                "................",
            ])
        case .picker:
            return fromMap([
                "................",
                "............kk..",
                "...........kkkk.",
                "..........kkkkk.",
                ".........kkkkk..",
                "........kgkkk...",
                ".......kwgk.....",
                "......kwgk......",
                ".....kwgk.......",
                "....kwgk........",
                "...kwgk.........",
                "..kwgk..........",
                "..kgk...........",
                ".kk.............",
                "................",
                "................",
            ])
        case .magnifier:
            return fromMap([
                "................",
                "...kkkk.........",
                "..kwwwwk........",
                ".kwwccwwk.......",
                ".kwcwwwwk.......",
                ".kwwwwwwk.......",
                ".kwwwwwwk.......",
                "..kwwwwk........",
                "...kkkkoo.......",
                "........ooo.....",
                ".........ooo....",
                "..........ooo...",
                "...........oo...",
                "................",
                "................",
                "................",
            ])
        case .airbrush:
            return fromMap([
                "................",
                "...........k.k..",
                ".........k..k...",
                "....kk.....k..k.",
                "...kssk.k.......",
                "...kkkk.........",
                "..kbbbbk........",
                "..kbwbbk........",
                "..kbwbbk........",
                "..kbwbbk........",
                "..kbwbbk........",
                "..kbbbbk........",
                "..kbbbbk........",
                "..kkkkkk........",
                "................",
                "................",
            ])
        case .text:
            return fromMap([
                "................",
                "................",
                ".......kk.......",
                "......kkkk......",
                "......kkkk......",
                ".....kk..kk.....",
                ".....kk..kk.....",
                "....kk....kk....",
                "....kkkkkkkk....",
                "...kk......kk...",
                "...kk......kk...",
                "..kkk......kkk..",
                ".kkkkk....kkkkk.",
                "................",
                "................",
                "................",
            ])
        }
        return b
    }
}

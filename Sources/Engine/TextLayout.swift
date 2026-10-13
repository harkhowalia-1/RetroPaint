import CoreGraphics
import CoreText
import Foundation

/// Text set in a fixed-width box. Coordinates are local to the box with a
/// top-left origin, in image pixels. Indices are UTF-16 offsets, matching
/// NSRange from the platform text views.
struct TextLayout {
    let frame: CTFrame
    let size: CGSize
    private let text: String
    private let lines: [CTLine]
    private let origins: [CGPoint]
    private let font: CTFont

    struct Style: Equatable {
        var fontName = "Helvetica"
        var size = 14
        var bold = false
        var italic = false
        var underline = false

        var font: CTFont {
            let base = CTFontCreateWithName(fontName as CFString, CGFloat(size), nil)
            var traits = CTFontSymbolicTraits()
            if bold { traits.insert(.traitBold) }
            if italic { traits.insert(.traitItalic) }
            guard !traits.isEmpty else { return base }
            return CTFontCreateCopyWithSymbolicTraits(base, CGFloat(size), nil, traits, traits) ?? base
        }
    }

    init(text: String, style: Style, color: RGBA, size: CGSize) {
        self.text = text
        self.size = size
        font = style.font
        let setter = CTFramesetterCreateWithAttributedString(Self.attributed(text, font: font, underline: style.underline, color: color))
        frame = CTFramesetterCreateFrame(setter, CFRange(location: 0, length: 0),
                                         CGPath(rect: CGRect(origin: .zero, size: size), transform: nil), nil)
        lines = CTFrameGetLines(frame) as? [CTLine] ?? []
        var o = [CGPoint](repeating: .zero, count: lines.count)
        CTFrameGetLineOrigins(frame, CFRange(location: 0, length: 0), &o)
        origins = o
    }

    private static func attributed(_ text: String, font: CTFont, underline: Bool, color: RGBA) -> NSAttributedString {
        var attrs: [NSAttributedString.Key: Any] = [
            NSAttributedString.Key(kCTFontAttributeName as String): font,
            NSAttributedString.Key(kCTForegroundColorAttributeName as String): color.cgColor,
        ]
        if underline {
            attrs[NSAttributedString.Key(kCTUnderlineStyleAttributeName as String)] = NSNumber(value: CTUnderlineStyle.single.rawValue)
        }
        return NSAttributedString(string: text, attributes: attrs)
    }

    /// Height needed to show all of `text` at `width`, including a trailing empty line.
    static func fittingHeight(text: String, style: Style, width: CGFloat) -> Int {
        let font = style.font
        let setter = CTFramesetterCreateWithAttributedString(attributed(text, font: font, underline: style.underline, color: .black))
        var h = CTFramesetterSuggestFrameSizeWithConstraints(setter, CFRange(location: 0, length: 0), nil,
                                                             CGSize(width: width, height: .greatestFiniteMagnitude), nil).height
        if text.isEmpty || text.hasSuffix("\n") { h += lineHeight(font) }
        return Int(h.rounded(.up)) + 2
    }

    static func lineHeight(_ font: CTFont) -> CGFloat {
        (CTFontGetAscent(font) + CTFontGetDescent(font) + CTFontGetLeading(font)).rounded(.up)
    }

    private var length: Int { text.utf16.count }

    /// Top and bottom of line `i`, measured from the top of the box.
    private func band(_ i: Int) -> (top: CGFloat, bottom: CGFloat) {
        var ascent: CGFloat = 0, descent: CGFloat = 0, leading: CGFloat = 0
        CTLineGetTypographicBounds(lines[i], &ascent, &descent, &leading)
        let baseline = size.height - origins[i].y
        return (baseline - ascent, baseline + descent)
    }

    func caret(at index: Int) -> CGRect {
        let asc = CTFontGetAscent(font), desc = CTFontGetDescent(font)
        guard !lines.isEmpty else { return CGRect(x: 0, y: 0, width: 1, height: (asc + desc).rounded(.up)) }
        // After a trailing newline the caret sits on a fresh line below the last one.
        if index >= length && text.hasSuffix("\n") {
            let b = band(lines.count - 1)
            let top = b.bottom + CTFontGetLeading(font)
            return CGRect(x: 0, y: top, width: 1, height: (asc + desc).rounded(.up))
        }
        for (i, line) in lines.enumerated() {
            let r = CTLineGetStringRange(line)
            let last = i == lines.count - 1
            if index < r.location + r.length || (last && index <= r.location + r.length) {
                let x = CTLineGetOffsetForStringIndex(line, index, nil)
                let b = band(i)
                return CGRect(x: origins[i].x + x, y: b.top, width: 1, height: b.bottom - b.top)
            }
        }
        return .zero
    }

    func highlightRects(_ range: NSRange) -> [CGRect] {
        guard range.length > 0 else { return [] }
        var out: [CGRect] = []
        for (i, line) in lines.enumerated() {
            let r = CTLineGetStringRange(line)
            let start = max(range.location, r.location), end = min(range.location + range.length, r.location + r.length)
            guard start < end else { continue }
            let x0 = CTLineGetOffsetForStringIndex(line, start, nil), x1 = CTLineGetOffsetForStringIndex(line, end, nil)
            let b = band(i)
            out.append(CGRect(x: origins[i].x + x0, y: b.top, width: max(1, x1 - x0), height: b.bottom - b.top))
        }
        return out
    }

    /// The string index nearest a point in the box.
    func index(at p: CGPoint) -> Int {
        for (i, line) in lines.enumerated() where p.y < band(i).bottom || i == lines.count - 1 {
            if i == lines.count - 1 && p.y >= band(i).bottom && text.hasSuffix("\n") { return length }
            let idx = CTLineGetStringIndexForPosition(line, CGPoint(x: p.x - origins[i].x, y: 0))
            return idx == kCFNotFound ? length : min(idx, length)
        }
        return length
    }
}

import SwiftUI

struct ToolButton: View {
    @ObservedObject var doc: PaintDocument
    let tool: Tool

    var body: some View {
        let selected = doc.tool == tool
        Button { doc.tool = tool } label: {
            ZStack {
                if selected { Dither() } else { XP.face }
                PixelIcon(image: ToolIcons.image(for: tool)).offset(x: selected ? 1 : 0, y: selected ? 1 : 0)
                if selected { Bevel(style: .sunken) } else { Bevel(style: .raised) }
            }
            .frame(width: 25, height: 25)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(tool.name)
        .accessibilityLabel(tool.name)
    }
}

/// The vertical toolbox: two columns of tools above the tool options box.
struct ToolBox: View {
    @ObservedObject var doc: PaintDocument

    var body: some View {
        VStack(spacing: 6) {
            Grid(horizontalSpacing: 0, verticalSpacing: 0) {
                ForEach(0..<8) { row in
                    GridRow {
                        ToolButton(doc: doc, tool: Tool(rawValue: row * 2)!)
                        ToolButton(doc: doc, tool: Tool(rawValue: row * 2 + 1)!)
                    }
                }
            }
            OptionsBox(doc: doc, axis: .vertical)
                .frame(width: 41, height: 66)
                .background(XP.face)
                .overlay(Bevel(style: .thinSunken))
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 3)
        .padding(.top, 4)
        .frame(width: 56)
        .background(XP.face)
    }
}

/// The options shown under the toolbox, which depend on the current tool.
struct OptionsBox: View {
    @ObservedObject var doc: PaintDocument
    var axis: Axis

    var body: some View {
        switch doc.tool {
        case .rectSelect, .freeSelect, .text:
            stack {
                option(selected: !doc.transparentSelection) { doc.transparentSelection = false } label: { TransparencyGlyph(transparent: false) }
                option(selected: doc.transparentSelection) { doc.transparentSelection = true } label: { TransparencyGlyph(transparent: true) }
            }
        case .eraser:
            stack {
                ForEach(Options.eraserSizes, id: \.self) { s in
                    option(selected: doc.eraserSize == s) { doc.eraserSize = s } label: { selected in
                        Rectangle().fill(selected ? Color.white : Color.black).frame(width: CGFloat(s), height: CGFloat(s))
                    }
                }
            }
        case .magnifier:
            stack {
                ForEach(Options.magnifierLevels, id: \.self) { z in
                    option(selected: doc.zoom == z) { doc.setZoom(z) } label: { selected in
                        Text("\(z)x").font(XP.font).foregroundStyle(selected ? Color.white : Color.black)
                    }
                }
            }
        case .brush:
            if axis == .vertical {
                Grid(horizontalSpacing: 0, verticalSpacing: 0) {
                    ForEach(0..<4) { row in
                        GridRow { ForEach(0..<3) { col in brushOption(BrushShape(rawValue: row * 3 + col)!) } }
                    }
                }
            } else {
                HStack(spacing: 0) { ForEach(BrushShape.allCases, id: \.self, content: brushOption) }
            }
        case .airbrush:
            stack {
                ForEach(Options.airbrushSizes, id: \.self) { s in
                    option(selected: doc.airbrushSize == s) { doc.airbrushSize = s } label: { selected in
                        SprayGlyph(size: s, color: selected ? .white : .black)
                    }
                }
            }
        case .line, .curve:
            stack {
                ForEach(Options.lineWidths, id: \.self) { w in
                    option(selected: doc.lineWidth == w) { doc.lineWidth = w } label: { selected in
                        Rectangle().fill(selected ? Color.white : Color.black).frame(width: 28, height: CGFloat(w))
                    }
                }
            }
        case .rectangle, .polygon, .ellipse, .roundedRectangle:
            stack {
                ForEach(FillStyle.allCases, id: \.self) { style in
                    option(selected: doc.fillStyle == style) { doc.fillStyle = style } label: { selected in
                        FillStyleGlyph(style: style, selected: selected)
                    }
                }
            }
        case .fill, .picker, .pencil:
            Color.clear
        }
    }

    @ViewBuilder private func stack<C: View>(@ViewBuilder _ content: () -> C) -> some View {
        if axis == .vertical {
            VStack(spacing: 0) { content() }.padding(2)
        } else {
            HStack(spacing: 4) { content() }.padding(.horizontal, 4)
        }
    }

    private func brushOption(_ shape: BrushShape) -> some View {
        option(selected: doc.brushShape == shape, compact: true) { doc.brushShape = shape } label: { selected in
            BrushGlyph(shape: shape, color: selected ? .white : .black)
        }
    }

    private func option<L: View>(selected: Bool, compact: Bool = false, action: @escaping () -> Void,
                                 @ViewBuilder label: @escaping (Bool) -> L) -> some View {
        Button(action: action) {
            label(selected)
                .frame(maxWidth: axis == .vertical ? .infinity : nil, maxHeight: axis == .vertical ? .infinity : nil)
                .frame(minWidth: compact ? 12 : (axis == .horizontal ? 36 : nil),
                       minHeight: compact ? 14 : (axis == .horizontal ? 30 : nil))
                .background(selected ? XP.navy : Color.clear)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func option<L: View>(selected: Bool, action: @escaping () -> Void, @ViewBuilder label: @escaping () -> L) -> some View {
        option(selected: selected, action: action) { _ in label() }
    }
}

private struct BrushGlyph: View {
    let shape: BrushShape
    let color: Color
    var body: some View {
        Canvas { ctx, size in
            let cx = Int(size.width / 2), cy = Int(size.height / 2)
            var p = Path()
            for o in shape.offsets { p.addRect(CGRect(x: cx + o.x, y: cy + o.y, width: 1, height: 1)) }
            ctx.fill(p, with: .color(color))
        }
        .frame(width: 11, height: 12)
    }
}

private struct SprayGlyph: View {
    let size: Int
    let color: Color
    var body: some View {
        Canvas { ctx, s in
            var rng = SeededRandom(seed: UInt64(size))
            var p = Path()
            let r = Double(size) / 2
            for _ in 0..<(size * 2) {
                let a = rng.next() * 2 * .pi, d = rng.next() * r
                p.addRect(CGRect(x: (s.width / 2 + cos(a) * d).rounded(), y: (s.height / 2 + sin(a) * d).rounded(), width: 1, height: 1))
            }
            ctx.fill(p, with: .color(color))
        }
        .frame(width: CGFloat(size) + 2, height: CGFloat(size) + 2)
    }
}

private struct SeededRandom {
    var state: UInt64
    init(seed: UInt64) { state = seed &* 0x9E37_79B9_7F4A_7C15 | 1 }
    mutating func next() -> Double {
        state ^= state << 13; state ^= state >> 7; state ^= state << 17
        return Double(state % 10_000) / 10_000
    }
}

private struct FillStyleGlyph: View {
    let style: FillStyle
    let selected: Bool
    var body: some View {
        let ink: Color = selected ? .white : .black
        ZStack {
            if style != .outline { Rectangle().fill(XP.darkShadow) }
            if style != .fillOnly { Rectangle().strokeBorder(ink, lineWidth: 1) }
        }
        .frame(width: 26, height: 12)
    }
}

private struct TransparencyGlyph: View {
    let transparent: Bool
    var body: some View {
        ZStack {
            Rectangle().fill(Color.white).frame(width: 26, height: 18).opacity(transparent ? 0 : 1)
            HStack(spacing: 2) {
                Circle().fill(Color.red).frame(width: 9, height: 9)
                Rectangle().fill(Color.blue).frame(width: 7, height: 10)
                Rectangle().fill(Color.green).frame(width: 7, height: 7).rotationEffect(.degrees(45))
            }
        }
        .frame(width: 30, height: 22)
        .overlay(Rectangle().strokeBorder(Color.black.opacity(0.5), lineWidth: 1))
    }
}

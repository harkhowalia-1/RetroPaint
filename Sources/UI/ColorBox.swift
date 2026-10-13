import SwiftUI

/// The foreground/background swatch: foreground on top, background behind.
struct CurrentColors: View {
    @ObservedObject var doc: PaintDocument

    var body: some View {
        ZStack(alignment: .topLeading) {
            XP.face
            swatch(doc.secondary).offset(x: 13, y: 13)
            swatch(doc.primary).offset(x: 5, y: 5)
        }
        .frame(width: 32, height: 32)
        .overlay(Bevel(style: .sunken))
        .accessibilityLabel("Current colors")
    }

    private func swatch(_ c: RGBA) -> some View {
        c.color.frame(width: 14, height: 14).overlay(Bevel(style: .sunken))
    }
}

struct PaletteSwatch: View {
    @ObservedObject var doc: PaintDocument
    let index: Int
    var size: CGFloat = 16
    @State private var lastTap = Date.distantPast

    var body: some View {
        doc.palette[index].color
            .frame(width: size, height: size)
            .overlay(Bevel(style: .sunken))
            .contentShape(Rectangle())
            .onTapGesture {
                // Select immediately; a quick second tap opens Edit Colors.
                doc.selectPalette(index, button: .primary)
                if Date().timeIntervalSince(lastTap) < 0.35 { doc.dialog = .editColors }
                lastTap = Date()
            }
            .onSecondaryAction { doc.selectPalette(index, button: .secondary) }
    }
}

/// The color box along the bottom of the window.
struct ColorBox: View {
    @ObservedObject var doc: PaintDocument

    var body: some View {
        HStack(alignment: .top, spacing: 2) {
            CurrentColors(doc: doc)
            Grid(horizontalSpacing: 0, verticalSpacing: 0) {
                ForEach(0..<2) { row in
                    GridRow {
                        ForEach(0..<Palette.columns, id: \.self) { col in PaletteSwatch(doc: doc, index: row * Palette.columns + col) }
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 5)
        .background(XP.face)
    }
}

struct StatusBar: View {
    @ObservedObject var doc: PaintDocument
    @ObservedObject var status: StatusModel

    init(doc: PaintDocument) {
        self.doc = doc
        status = doc.status
    }

    var body: some View {
        HStack(spacing: 2) {
            panel(doc.tool.help, maxWidth: .infinity)
            panel(status.cursor.map { "\($0.x),\($0.y)" } ?? "", width: 90)
            panel(status.extent.map { "\($0.width)x\($0.height)" } ?? "", width: 90)
        }
        .padding(2)
        .font(XP.font)
        .foregroundStyle(.black)
        .background(XP.face)
    }

    private func panel(_ text: String, width: CGFloat? = nil, maxWidth: CGFloat? = nil) -> some View {
        Text(text)
            .lineLimit(1)
            .padding(.horizontal, 4)
            .frame(width: width, alignment: .leading)
            .frame(maxWidth: maxWidth, alignment: .leading)
            .frame(height: 18)
            .overlay(Bevel(style: .thinSunken))
    }
}

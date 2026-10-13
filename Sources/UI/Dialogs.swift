import SwiftUI

/// Classic dialog chrome: beige face, title, OK/Cancel on the right.
struct XPDialog<Content: View>: View {
    let title: String
    var okTitle = "OK"
    var showsCancel = true
    let onOK: () -> Void
    @ViewBuilder let content: () -> Content
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(title).font(.system(size: 13, weight: .bold)).foregroundStyle(.white)
                Spacer()
            }
            .padding(.horizontal, 8)
            .frame(height: 26)
            .background(LinearGradient(colors: [Color(red: 0.0, green: 0.33, blue: 0.89), Color(red: 0.24, green: 0.58, blue: 1.0)],
                                       startPoint: .leading, endPoint: .trailing))
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 10) { content() }
                    .frame(maxWidth: .infinity, alignment: .leading)
                VStack(spacing: 6) {
                    XPButton(okTitle) { onOK(); dismiss() }.keyboardShortcut(.defaultAction)
                    if showsCancel { XPButton("Cancel") { dismiss() }.keyboardShortcut(.cancelAction) }
                }
            }
            .padding(12)
        }
        .font(XP.font)
        .foregroundStyle(.black)
        .background(XP.face)
        .frame(minWidth: 320)
        .presentationDetents([.medium, .large])
    }
}

struct XPButton: View {
    let title: String
    let action: () -> Void
    init(_ title: String, action: @escaping () -> Void) { self.title = title; self.action = action }

    var body: some View {
        Button(action: action) {
            Text(title).font(XP.font).foregroundStyle(.black)
                .frame(width: 75, height: 23)
                .background(XP.face)
                .overlay(Bevel(style: .raised))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

struct GroupBoxXP<Content: View>: View {
    let title: String
    @ViewBuilder let content: () -> Content
    var body: some View {
        VStack(alignment: .leading, spacing: 6) { content() }
            .padding(10)
            .padding(.top, 4)
            .overlay(RoundedRectangle(cornerRadius: 3).stroke(XP.shadow))
            .overlay(alignment: .topLeading) {
                Text(title).padding(.horizontal, 3).background(XP.face).offset(x: 8, y: -7)
            }
            .padding(.top, 6)
    }
}

struct NumberField: View {
    let label: String
    @Binding var value: Int
    var suffix = ""
    var body: some View {
        HStack {
            Text(label).frame(minWidth: 70, alignment: .leading)
            TextField("", value: $value, format: .number)
                .textFieldStyle(.plain)
                .padding(.horizontal, 3)
                .frame(width: 60, height: 20)
                .background(Color.white)
                .overlay(Bevel(style: .sunken))
                #if os(iOS)
                .keyboardType(.numberPad)
                #endif
            Text(suffix)
        }
    }
}

struct RadioRow: View {
    let title: String
    let selected: Bool
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                ZStack {
                    Circle().fill(Color.white).overlay(Circle().stroke(XP.darkShadow))
                    if selected { Circle().fill(Color(red: 0.13, green: 0.6, blue: 0.13)).padding(3) }
                }
                .frame(width: 13, height: 13)
                Text(title)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

struct DialogHost: View {
    @ObservedObject var doc: PaintDocument
    let kind: DialogKind

    var body: some View {
        switch kind {
        case .attributes: AttributesDialog(doc: doc)
        case .flipRotate: FlipRotateDialog(doc: doc)
        case .stretchSkew: StretchSkewDialog(doc: doc)
        case .customZoom: CustomZoomDialog(doc: doc)
        case .editColors: EditColorsDialog(doc: doc)
        case .about: AboutDialog()
        case .helpTopics: HelpDialog()
        }
    }
}

struct AttributesDialog: View {
    @ObservedObject var doc: PaintDocument
    @State private var width = 0
    @State private var height = 0

    var body: some View {
        XPDialog(title: "Attributes", onOK: { doc.setAttributes(width: max(1, min(width, 8000)), height: max(1, min(height, 8000))) }) {
            Text("File last saved: Not Available")
            Text("Size on disk: Not Available")
            GroupBoxXP(title: "Units: Pixels") {
                NumberField(label: "Width:", value: $width)
                NumberField(label: "Height:", value: $height)
            }
            XPButton("Default") { width = 640; height = 480 }
        }
        .onAppear { width = doc.canvasSize.width; height = doc.canvasSize.height }
    }
}

struct FlipRotateDialog: View {
    @ObservedObject var doc: PaintDocument
    private enum Choice { case flipH, flipV, rotate }
    @State private var choice = Choice.flipH
    @State private var turns = 1

    var body: some View {
        XPDialog(title: "Flip and Rotate", onOK: apply) {
            GroupBoxXP(title: "Flip or rotate") {
                RadioRow(title: "Flip horizontal", selected: choice == .flipH) { choice = .flipH }
                RadioRow(title: "Flip vertical", selected: choice == .flipV) { choice = .flipV }
                RadioRow(title: "Rotate by angle", selected: choice == .rotate) { choice = .rotate }
                VStack(alignment: .leading, spacing: 4) {
                    ForEach([1, 2, 3], id: \.self) { t in
                        RadioRow(title: "\(t * 90)°", selected: turns == t) { turns = t; choice = .rotate }
                    }
                }
                .padding(.leading, 24)
                .opacity(choice == .rotate ? 1 : 0.5)
            }
        }
    }

    private func apply() {
        switch choice {
        case .flipH: doc.flip(horizontal: true)
        case .flipV: doc.flip(horizontal: false)
        case .rotate: doc.rotate(quarterTurns: turns)
        }
    }
}

struct StretchSkewDialog: View {
    @ObservedObject var doc: PaintDocument
    @State private var h = 100
    @State private var v = 100
    @State private var skewH = 0
    @State private var skewV = 0

    var body: some View {
        XPDialog(title: "Stretch and Skew", onOK: {
            doc.stretchSkew(horizontalPercent: max(1, min(h, 500)), verticalPercent: max(1, min(v, 500)),
                            horizontalSkew: Double(max(-89, min(skewH, 89))), verticalSkew: Double(max(-89, min(skewV, 89))))
        }) {
            GroupBoxXP(title: "Stretch") {
                NumberField(label: "Horizontal:", value: $h, suffix: "%")
                NumberField(label: "Vertical:", value: $v, suffix: "%")
            }
            GroupBoxXP(title: "Skew") {
                NumberField(label: "Horizontal:", value: $skewH, suffix: "Degrees")
                NumberField(label: "Vertical:", value: $skewV, suffix: "Degrees")
            }
        }
    }
}

struct CustomZoomDialog: View {
    @ObservedObject var doc: PaintDocument
    @State private var zoom = 1

    var body: some View {
        XPDialog(title: "Custom Zoom", onOK: { doc.setZoom(zoom) }) {
            Text("Current zoom: \(doc.zoom * 100)%")
            GroupBoxXP(title: "Zoom to") {
                ForEach([1, 2, 4, 6, 8], id: \.self) { z in
                    RadioRow(title: "\(z * 100)%", selected: zoom == z) { zoom = z }
                }
            }
        }
        .onAppear { zoom = doc.zoom }
    }
}

struct EditColorsDialog: View {
    @ObservedObject var doc: PaintDocument
    @State private var color = RGBA.black.cgColor

    var body: some View {
        XPDialog(title: "Edit Colors", okTitle: "OK", onOK: {
            if let c = RGBA(cgColor: color) { doc.defineCustomColor(c) }
        }) {
            Text("Basic colors:")
            Grid(horizontalSpacing: 3, verticalSpacing: 3) {
                ForEach(0..<4) { row in
                    GridRow {
                        ForEach(0..<7) { col in
                            let c = Palette.standard[(row * 7 + col) % Palette.standard.count]
                            c.color.frame(width: 18, height: 14).overlay(Bevel(style: .sunken))
                                .onTapGesture { color = c.cgColor }
                        }
                    }
                }
            }
            ColorPicker("Define Custom Color:", selection: $color, supportsOpacity: false)
            HStack {
                Text("Color|Solid")
                Color(cgColor: color).frame(width: 60, height: 30).overlay(Bevel(style: .sunken))
            }
        }
        .onAppear { color = doc.palette[doc.selectedPaletteIndex].cgColor }
    }
}

struct AboutDialog: View {
    var body: some View {
        XPDialog(title: "About RetroPaint", showsCancel: false, onOK: {}) {
            HStack(spacing: 12) {
                PixelIcon(image: ToolIcons.image(for: .brush)).scaleEffect(2).frame(width: 32, height: 32)
                VStack(alignment: .leading, spacing: 4) {
                    Text("RetroPaint").bold()
                    Text("Version 1.0")
                    Text("A classic bitmap editor for Mac, iPad and iPhone.")
                }
            }
        }
    }
}

struct HelpDialog: View {
    var body: some View {
        XPDialog(title: "Help Topics", showsCancel: false, onOK: {}) {
            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(Tool.allCases) { tool in
                        HStack(alignment: .top, spacing: 8) {
                            PixelIcon(image: ToolIcons.image(for: tool))
                            VStack(alignment: .leading) {
                                Text(tool.name).bold()
                                Text(tool.help)
                            }
                        }
                    }
                    Divider()
                    Text("Left click draws with the foreground color, right click with the background color. On iPad and iPhone, long-press a palette color to set the background color. Hold Shift for straight lines, squares and circles. With the Text tool, drag a box (or click) and type; click outside the box to finish. Two fingers scroll the picture; pinch to zoom.")
                }
            }
            .frame(maxHeight: 360)
        }
    }
}

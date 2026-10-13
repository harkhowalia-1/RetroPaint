import SwiftUI

/// The floating "Fonts" toolbar shown while typing with the Text tool.
struct FontsToolbar: View {
    @ObservedObject var doc: PaintDocument
    var showsTitle = true

    static let fonts = ["Helvetica", "Arial", "Times New Roman", "Courier New", "Georgia", "Verdana",
                        "Trebuchet MS", "Comic Sans MS", "Menlo"]
    static let sizes = [8, 9, 10, 11, 12, 14, 16, 18, 20, 22, 24, 26, 28, 36, 48, 72]

    var body: some View {
        VStack(spacing: 0) {
            if showsTitle {
                XPTitleBar(title: "Fonts", toolWindow: true) { doc.showTextToolbar = false }
            }
            HStack(spacing: 4) {
                Menu {
                    Picker("Font", selection: $doc.textStyle.fontName) {
                        ForEach(Self.fonts, id: \.self) { Text($0).tag($0) }
                    }
                } label: {
                    field(doc.textStyle.fontName, width: 130)
                }
                .menuStyle(.button).buttonStyle(.plain).menuIndicator(.hidden).fixedSize()
                Menu {
                    Picker("Size", selection: $doc.textStyle.size) {
                        ForEach(Self.sizes, id: \.self) { Text("\($0)").tag($0) }
                    }
                } label: {
                    field("\(doc.textStyle.size)", width: 40)
                }
                .menuStyle(.button).buttonStyle(.plain).menuIndicator(.hidden).fixedSize()
                styleButton(Text("B").bold(), isOn: $doc.textStyle.bold)
                styleButton(Text("I").italic(), isOn: $doc.textStyle.italic)
                styleButton(Text("U").underline(), isOn: $doc.textStyle.underline)
                if !showsTitle { XPCloseButton(size: 18) { doc.showTextToolbar = false } }
            }
            .padding(4)
        }
        .font(XP.font)
        .foregroundStyle(.black)
        .background(XP.face)
        .overlay(Bevel(style: .raised))
        .fixedSize()
    }

    private func field(_ text: String, width: CGFloat) -> some View {
        HStack(spacing: 0) {
            Text(text).lineLimit(1).padding(.horizontal, 3).frame(width: width, alignment: .leading)
            Image(systemName: "chevron.down").font(.system(size: 8, weight: .bold))
                .frame(width: 16, height: 20).background(XP.face).overlay(Bevel(style: .raised))
        }
        .frame(height: 22)
        .background(Color.white)
        .overlay(Bevel(style: .sunken))
    }

    private func styleButton(_ label: Text, isOn: Binding<Bool>) -> some View {
        Button { isOn.wrappedValue.toggle() } label: {
            label.frame(width: 23, height: 22)
                .background(isOn.wrappedValue ? AnyView(Dither()) : AnyView(XP.face))
                .overlay(Bevel(style: isOn.wrappedValue ? .sunken : .raised))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

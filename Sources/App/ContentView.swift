import SwiftUI

struct ContentView: View {
    @StateObject private var doc = PaintDocument()
    #if os(iOS)
    @Environment(\.horizontalSizeClass) private var sizeClass
    private var compact: Bool { sizeClass == .compact }
    #else
    private let compact = false
    #endif

    var body: some View {
        Group {
            if compact { CompactLayout(doc: doc) } else { ClassicLayout(doc: doc) }
        }
        .environment(\.colorScheme, .light)
        .focusedSceneObject(doc)
        .navigationTitle("\(doc.fileName) - RetroPaint")
        .fileImporter(isPresented: Binding(get: { doc.importMode != nil }, set: { if !$0 { doc.importMode = nil } }),
                      allowedContentTypes: [.image]) { result in
            if let mode = doc.importMode { doc.handleImport(result, mode: mode) }
            doc.importMode = nil
        }
        .fileExporter(isPresented: Binding(get: { doc.exportMode != nil }, set: { if !$0 { doc.exportMode = nil } }),
                      document: doc.exportMode.map { ImageFile(bitmap: doc.exportBitmap(for: $0)) },
                      contentTypes: ImageFile.writableContentTypes,
                      defaultFilename: doc.exportMode == .copyTo ? "selection" : (doc.fileName as NSString).deletingPathExtension) { result in
            if let mode = doc.exportMode { doc.handleExport(result, mode: mode) }
            doc.exportMode = nil
        }
        .sheet(item: $doc.dialog) { DialogHost(doc: doc, kind: $0).environment(\.colorScheme, .light) }
        .confirmationDialog("Save changes to \(doc.fileName)?", isPresented: $doc.confirmingNew, titleVisibility: .visible) {
            Button("Save") { doc.save() }
            Button("Don't Save", role: .destructive) { doc.newImage() }
            Button("Cancel", role: .cancel) {}
        }
        .alert("RetroPaint", isPresented: Binding(get: { doc.errorMessage != nil }, set: { if !$0 { doc.errorMessage = nil } })) {
            Button("OK") {}
        } message: {
            Text(doc.errorMessage ?? "")
        }
        .overlay { if doc.viewingBitmap { BitmapViewer(doc: doc) } }
    }
}

/// Mac and iPad: the original window layout.
struct ClassicLayout: View {
    @ObservedObject var doc: PaintDocument

    var body: some View {
        VStack(spacing: 0) {
            XPMenuBar(doc: doc)
            HStack(spacing: 0) {
                if doc.showToolBox { ToolBox(doc: doc) }
                CanvasHost(doc: doc)
                    .overlay(Bevel(style: .sunken))
                    .overlay(alignment: .topTrailing) { if doc.showThumbnail && doc.zoom > 1 { Thumbnail(doc: doc) } }
            }
            if doc.showColorBox { ColorBox(doc: doc) }
            if doc.showStatusBar { StatusBar(doc: doc) }
        }
        .background(XP.face)
        #if os(macOS)
        .frame(minWidth: 600, minHeight: 440)
        #endif
    }
}

/// iPhone: same look, re-flowed for a narrow screen.
struct CompactLayout: View {
    @ObservedObject var doc: PaintDocument

    var body: some View {
        let m = MenuSet(doc: doc, commands: false)
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Menu {
                    Menu("File") { m.file }
                    Menu("Edit") { m.edit }
                    Menu("View") { m.view }
                    Menu("Image") { m.image }
                    Menu("Colors") { m.colors }
                    Menu("Help") { m.help }
                } label: {
                    Image(systemName: "line.3.horizontal").frame(width: 36, height: 30)
                        .background(XP.face).overlay(Bevel(style: .raised))
                }
                Text("\(doc.fileName) - RetroPaint").font(.system(size: 14, weight: .bold)).foregroundStyle(.white).lineLimit(1)
                Spacer()
                barButton("arrow.uturn.backward", enabled: doc.canUndo) { doc.undo() }
                barButton("arrow.uturn.forward", enabled: doc.canRedo) { doc.redo() }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(LinearGradient(colors: [Color(red: 0.0, green: 0.33, blue: 0.89), Color(red: 0.24, green: 0.58, blue: 1.0)],
                                       startPoint: .leading, endPoint: .trailing))

            CanvasHost(doc: doc).overlay(Bevel(style: .sunken))

            if doc.showStatusBar {
                StatusBar(doc: doc)
            }
            ScrollView(.horizontal, showsIndicators: false) {
                OptionsBox(doc: doc, axis: .horizontal).frame(height: 34)
            }
            .frame(height: 36)
            .background(XP.face)
            .overlay(Bevel(style: .thinSunken))

            HStack(spacing: 4) {
                CurrentColors(doc: doc)
                ScrollView(.horizontal, showsIndicators: false) {
                    Grid(horizontalSpacing: 0, verticalSpacing: 0) {
                        ForEach(0..<2) { row in
                            GridRow {
                                ForEach(0..<Palette.columns, id: \.self) { col in
                                    PaletteSwatch(doc: doc, index: row * Palette.columns + col, size: 22)
                                }
                            }
                        }
                    }
                }
            }
            .padding(4)
            .background(XP.face)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 0) {
                    ForEach(Tool.allCases) { ToolButton(doc: doc, tool: $0).scaleEffect(1.4).frame(width: 36, height: 36) }
                }
                .padding(.horizontal, 4)
            }
            .padding(.vertical, 2)
            .background(XP.face)
        }
        .background(XP.face)
    }

    private func barButton(_ symbol: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).foregroundStyle(.black).frame(width: 34, height: 30)
                .background(XP.face).overlay(Bevel(style: .raised))
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.5)
    }
}

/// Small 1:1 preview of the picture while zoomed in.
struct Thumbnail: View {
    @ObservedObject var doc: PaintDocument

    var body: some View {
        VStack(spacing: 0) {
            Text("Thumbnail").font(XP.font).foregroundStyle(.white).frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 4).frame(height: 16).background(XP.selection)
            if let img = doc.cgImage {
                Image(decorative: img, scale: 1).interpolation(.none).resizable().aspectRatio(contentMode: .fit)
            }
        }
        .frame(width: 160, height: 136)
        .background(XP.face)
        .overlay(Bevel(style: .raised))
        .padding(12)
    }
}

/// View Bitmap: the picture alone, full screen; any click returns.
struct BitmapViewer: View {
    @ObservedObject var doc: PaintDocument

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            if let img = doc.cgImage {
                Image(decorative: img, scale: 1).interpolation(.none).resizable().aspectRatio(contentMode: .fit)
                    .frame(maxWidth: CGFloat(doc.canvasSize.width), maxHeight: CGFloat(doc.canvasSize.height))
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { doc.viewingBitmap = false }
    }
}

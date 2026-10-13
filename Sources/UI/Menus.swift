import SwiftUI

/// Menu contents shared by the in-window menu bar and the system menu / keyboard shortcuts.
@MainActor
struct MenuSet {
    @ObservedObject var doc: PaintDocument
    /// True when building system commands, which own the keyboard shortcuts.
    var commands: Bool

    private var editingText: Bool { doc.dialog != nil }

    @ViewBuilder var file: some View {
        Button("New") { doc.requestNew() }.shortcut("n", if: commands)
        Button("Open...") { doc.importMode = .open }.shortcut("o", if: commands)
        Button("Save") { doc.save() }.shortcut("s", if: commands)
        Button("Save As...") { doc.exportMode = .saveAs }.shortcut("s", [.command, .shift], if: commands)
        Divider()
        Button("Print...") { doc.finishDrafts(); doc.commitSelection(); Printer.print(doc.image) }.shortcut("p", if: commands)
        ShareLink("Send...", item: SharedPicture(bitmap: doc.image, name: doc.fileName),
                  preview: SharePreview(doc.fileName))
        #if os(macOS)
        if !commands {
            Divider()
            Button("Exit") { NSApp.terminate(nil) }
        }
        #endif
    }

    @ViewBuilder var edit: some View {
        Button("Undo") { editingText ? StandardEdit.undo.send() : doc.undo() }
            .shortcut("z", if: commands).disabled(!commands && !doc.canUndo)
        Button("Repeat") { editingText ? StandardEdit.redo.send() : doc.redo() }
            .shortcut("y", if: commands).disabled(!commands && !doc.canRedo)
        Divider()
        Button("Cut") { editingText ? StandardEdit.cut.send() : doc.cut() }
            .shortcut("x", if: commands).disabled(!commands && !doc.hasSelection)
        Button("Copy") { editingText ? StandardEdit.copy.send() : doc.copy() }
            .shortcut("c", if: commands).disabled(!commands && !doc.hasSelection)
        Button("Paste") { editingText ? StandardEdit.paste.send() : doc.paste() }.shortcut("v", if: commands)
        Button("Clear Selection") { doc.deleteSelection() }.disabled(!doc.hasSelection)
        Button("Select All") { editingText ? StandardEdit.selectAll.send() : doc.selectAll() }.shortcut("a", if: commands)
        Divider()
        Button("Copy To...") { doc.exportMode = .copyTo }.disabled(!doc.hasSelection)
        Button("Paste From...") { doc.importMode = .pasteFrom }
    }

    @ViewBuilder var view: some View {
        Toggle("Tool Box", isOn: $doc.showToolBox).shortcut("t", if: commands)
        Toggle("Color Box", isOn: $doc.showColorBox).shortcut("l", if: commands)
        Toggle("Status Bar", isOn: $doc.showStatusBar)
        Divider()
        Menu("Zoom") {
            Button("Normal Size") { doc.setZoom(1) }.shortcut(.pageUp, if: commands)
            Button("Large Size") { doc.setZoom(4) }.shortcut(.pageDown, if: commands)
            Button("Custom...") { doc.dialog = .customZoom }
            Divider()
            Toggle("Show Grid", isOn: $doc.showGrid).shortcut("g", if: commands).disabled(doc.zoom < 4)
            Toggle("Show Thumbnail", isOn: $doc.showThumbnail).disabled(doc.zoom < 2)
        }
        Button("View Bitmap") { doc.finishDrafts(); doc.commitSelection(); doc.viewingBitmap = true }.shortcut("f", if: commands)
    }

    @ViewBuilder var image: some View {
        Button("Flip/Rotate...") { doc.dialog = .flipRotate }.shortcut("r", if: commands)
        Button("Stretch/Skew...") { doc.dialog = .stretchSkew }.shortcut("w", [.command, .shift], if: commands)
        Button("Invert Colors") { doc.invertColors() }.shortcut("i", if: commands)
        Button("Attributes...") { doc.dialog = .attributes }.shortcut("e", if: commands)
        Button("Clear Image") { doc.clearImage() }.shortcut("n", [.command, .shift], if: commands)
        Toggle("Draw Opaque", isOn: Binding(get: { !doc.transparentSelection }, set: { doc.transparentSelection = !$0 }))
    }

    @ViewBuilder var colors: some View {
        Button("Edit Colors...") { doc.dialog = .editColors }
    }

    @ViewBuilder var help: some View {
        Button("Help Topics") { doc.dialog = .helpTopics }
        Divider()
        Button("About RetroPaint") { doc.dialog = .about }
    }
}

/// The classic menu bar strip inside the window.
struct XPMenuBar: View {
    @ObservedObject var doc: PaintDocument

    var body: some View {
        let m = MenuSet(doc: doc, commands: false)
        HStack(spacing: 0) {
            item("File") { m.file }
            item("Edit") { m.edit }
            item("View") { m.view }
            item("Image") { m.image }
            item("Colors") { m.colors }
            item("Help") { m.help }
            Spacer()
        }
        .padding(.horizontal, 2)
        .frame(height: 22)
        .background(XP.face)
        .overlay(alignment: .bottom) { XP.highlight.frame(height: 1) }
    }

    private func item<C: View>(_ title: String, @ViewBuilder content: () -> C) -> some View {
        Menu {
            content()
        } label: {
            Text(title).font(XP.font).foregroundStyle(.black).padding(.horizontal, 6).padding(.vertical, 2)
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
    }
}

struct PaintCommands: Commands {
    @FocusedObject var doc: PaintDocument?

    var body: some Commands {
        CommandGroup(replacing: .newItem) { if let doc { MenuSet(doc: doc, commands: true).file } }
        CommandGroup(replacing: .saveItem) {}
        CommandGroup(replacing: .printItem) {}
        CommandGroup(replacing: .undoRedo) { if let doc { MenuSet(doc: doc, commands: true).edit } }
        CommandGroup(replacing: .pasteboard) {}
        CommandGroup(before: .toolbar) { if let doc { MenuSet(doc: doc, commands: true).view } }
        CommandMenu("Image") { if let doc { MenuSet(doc: doc, commands: true).image } }
        CommandMenu("Colors") { if let doc { MenuSet(doc: doc, commands: true).colors } }
        CommandGroup(replacing: .help) { if let doc { MenuSet(doc: doc, commands: true).help } }
    }
}

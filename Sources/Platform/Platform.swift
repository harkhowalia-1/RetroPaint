import SwiftUI
import UniformTypeIdentifiers
#if os(macOS)
import AppKit
#else
import UIKit
#endif

enum Clipboard {
    static func write(_ b: Bitmap) {
        guard let png = b.encoded(as: .png) else { return }
        #if os(macOS)
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setData(png, forType: .png)
        if let cg = b.makeCGImage(), let tiff = NSBitmapImageRep(cgImage: cg).tiffRepresentation {
            pb.setData(tiff, forType: .tiff)
        }
        #else
        UIPasteboard.general.setData(png, forPasteboardType: UTType.png.identifier)
        #endif
    }

    static func read() -> Bitmap? {
        #if os(macOS)
        let pb = NSPasteboard.general
        guard let data = pb.data(forType: .png) ?? pb.data(forType: .tiff) else { return nil }
        return Bitmap(data: data)
        #else
        let pb = UIPasteboard.general
        if let data = pb.data(forPasteboardType: UTType.png.identifier) { return Bitmap(data: data) }
        if let cg = pb.image?.cgImage { return Bitmap(cgImage: cg) }
        return nil
        #endif
    }
}

enum Printer {
    @MainActor
    static func print(_ b: Bitmap) {
        guard let cg = b.makeCGImage() else { return }
        #if os(macOS)
        let view = NSImageView(frame: NSRect(x: 0, y: 0, width: b.width, height: b.height))
        view.image = NSImage(cgImage: cg, size: NSSize(width: b.width, height: b.height))
        NSPrintOperation(view: view).run()
        #else
        let controller = UIPrintInteractionController.shared
        controller.printingItem = UIImage(cgImage: cg)
        controller.present(animated: true)
        #endif
    }
}

/// Routes Cut/Copy/Paste/Undo to the focused text field while a dialog is open.
enum StandardEdit {
    case cut, copy, paste, selectAll, undo, redo

    @MainActor
    func send() {
        #if os(macOS)
        let sel: Selector = switch self {
        case .cut: #selector(NSText.cut(_:))
        case .copy: #selector(NSText.copy(_:))
        case .paste: #selector(NSText.paste(_:))
        case .selectAll: #selector(NSText.selectAll(_:))
        case .undo: Selector(("undo:"))
        case .redo: Selector(("redo:"))
        }
        NSApp.sendAction(sel, to: nil, from: nil)
        #else
        let sel: Selector = switch self {
        case .cut: #selector(UIResponderStandardEditActions.cut(_:))
        case .copy: #selector(UIResponderStandardEditActions.copy(_:))
        case .paste: #selector(UIResponderStandardEditActions.paste(_:))
        case .selectAll: #selector(UIResponderStandardEditActions.selectAll(_:))
        case .undo: Selector(("undo:"))
        case .redo: Selector(("redo:"))
        }
        UIApplication.shared.sendAction(sel, to: nil, from: nil, for: nil)
        #endif
    }
}

struct ImageFile: FileDocument {
    static var readableContentTypes: [UTType] { [.png, .bmp, .jpeg, .gif, .tiff] }
    static var writableContentTypes: [UTType] { [.png, .bmp, .jpeg, .gif, .tiff] }

    var bitmap: Bitmap

    init(bitmap: Bitmap) { self.bitmap = bitmap }

    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents, let b = Bitmap(data: data) else {
            throw CocoaError(.fileReadCorruptFile)
        }
        bitmap = b
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        guard let data = bitmap.encoded(as: configuration.contentType) else { throw CocoaError(.fileWriteUnknown) }
        return FileWrapper(regularFileWithContents: data)
    }
}

/// PNG wrapper for the share sheet ("Send...").
struct SharedPicture: Transferable {
    var bitmap: Bitmap
    var name: String

    static var transferRepresentation: some TransferRepresentation {
        DataRepresentation(exportedContentType: .png) { $0.bitmap.encoded(as: .png) ?? Data() }
            .suggestedFileName { $0.name }
    }
}

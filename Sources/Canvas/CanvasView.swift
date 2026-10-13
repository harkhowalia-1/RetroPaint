import SwiftUI

#if os(macOS)
import AppKit

private final class FlippedClipView: NSClipView {
    override var isFlipped: Bool { true }
}

final class CanvasNSView: NSView {
    let doc: PaintDocument
    private var activeButton: PointerButton?

    init(doc: PaintDocument) {
        self.doc = doc
        super.init(frame: .zero)
    }

    @available(*, unavailable) required init?(coder: NSCoder) { fatalError() }

    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        CanvasRenderer.draw(doc, in: ctx, dirty: dirtyRect)
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseMoved, .mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect, .cursorUpdate], owner: self))
    }

    private func location(_ e: NSEvent) -> CGPoint { convert(e.locationInWindow, from: nil) }
    private func imagePoint(_ e: NSEvent) -> CGPoint { CanvasGeometry.imagePoint(location(e), zoom: doc.zoom) }

    private func down(_ e: NSEvent, _ button: PointerButton) {
        window?.makeFirstResponder(self)
        guard activeButton == nil else { return }
        activeButton = button
        let handle = CanvasGeometry.handle(at: location(e), size: doc.canvasSize, zoom: doc.zoom, slop: 2)
        doc.pointerDown(imagePoint(e), handle: handle, button: button,
                        shift: e.modifierFlags.contains(.shift),
                        duplicate: e.modifierFlags.contains(.control) || e.modifierFlags.contains(.option),
                        clickCount: e.clickCount)
    }

    private func drag(_ e: NSEvent, _ button: PointerButton) {
        guard activeButton == button else { return }
        autoscroll(with: e)
        doc.pointerMoved(imagePoint(e), shift: e.modifierFlags.contains(.shift))
    }

    private func up(_ e: NSEvent, _ button: PointerButton) {
        guard activeButton == button else { return }
        activeButton = nil
        doc.pointerUp(imagePoint(e), shift: e.modifierFlags.contains(.shift), clickCount: e.clickCount)
    }

    override func mouseDown(with e: NSEvent) { down(e, e.modifierFlags.contains(.control) && doc.tool != .rectSelect && doc.tool != .freeSelect ? .secondary : .primary) }
    override func mouseDragged(with e: NSEvent) { drag(e, activeButton ?? .primary) }
    override func mouseUp(with e: NSEvent) { up(e, activeButton ?? .primary) }
    override func rightMouseDown(with e: NSEvent) { down(e, .secondary) }
    override func rightMouseDragged(with e: NSEvent) { drag(e, .secondary) }
    override func rightMouseUp(with e: NSEvent) { up(e, .secondary) }

    override func mouseMoved(with e: NSEvent) {
        doc.hover(imagePoint(e))
        updateCursor(e)
    }

    override func mouseExited(with e: NSEvent) { doc.hover(nil) }
    override func cursorUpdate(with e: NSEvent) { updateCursor(e) }

    private func updateCursor(_ e: NSEvent) {
        if let h = CanvasGeometry.handle(at: location(e), size: doc.canvasSize, zoom: doc.zoom, slop: 2) {
            switch h {
            case .right: NSCursor.resizeLeftRight.set()
            case .bottom: NSCursor.resizeUpDown.set()
            case .corner: NSCursor.crosshair.set()
            }
        } else if CanvasGeometry.imageRect(doc.canvasSize, zoom: doc.zoom).contains(location(e)) {
            ToolCursors.cursor(for: doc.tool).set()
        } else {
            NSCursor.arrow.set()
        }
    }

    override func keyDown(with e: NSEvent) {
        switch e.keyCode {
        case 51, 117: doc.deleteSelection()
        case 53: doc.cancel()
        default: super.keyDown(with: e)
        }
    }
}

@MainActor
enum ToolCursors {
    private static var cache: [Tool: NSCursor] = [:]

    static func cursor(for tool: Tool) -> NSCursor {
        if let c = cache[tool] { return c }
        let hotspot: NSPoint? = switch tool {
        case .pencil: NSPoint(x: 1, y: 13)
        case .fill: NSPoint(x: 14, y: 13)
        case .picker: NSPoint(x: 1, y: 13)
        case .magnifier: NSPoint(x: 5, y: 5)
        default: nil
        }
        guard let hotspot, let cg = ToolIcons.image(for: tool) else { return .crosshair }
        let cursor = NSCursor(image: NSImage(cgImage: cg, size: NSSize(width: 16, height: 16)), hotSpot: hotspot)
        cache[tool] = cursor
        return cursor
    }
}

struct CanvasHost: NSViewRepresentable {
    @ObservedObject var doc: PaintDocument

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSScrollView()
        scroll.contentView = FlippedClipView()
        scroll.hasVerticalScroller = true
        scroll.hasHorizontalScroller = true
        scroll.autohidesScrollers = true
        scroll.backgroundColor = NSColor(cgColor: CanvasColors.workspace) ?? .gray
        scroll.drawsBackground = true
        let canvas = CanvasNSView(doc: doc)
        scroll.documentView = canvas
        doc.onCanvasChange = { [weak canvas] in canvas?.needsDisplay = true }
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        guard let canvas = scroll.documentView else { return }
        let size = CanvasGeometry.contentSize(doc.canvasSize, zoom: doc.zoom)
        if canvas.frame.size != size { canvas.setFrameSize(size) }
        canvas.needsDisplay = true
        if let c = doc.pendingScrollCenter {
            DispatchQueue.main.async {
                let visible = scroll.contentView.bounds.size
                let z = CGFloat(doc.zoom)
                canvas.scroll(CGPoint(x: CanvasGeometry.inset + c.x * z - visible.width / 2,
                                      y: CanvasGeometry.inset + c.y * z - visible.height / 2))
                doc.pendingScrollCenter = nil
            }
        }
    }
}

#else
import UIKit

/// A scroll view that is also the drawing surface: it repaints its visible
/// bounds on every scroll, so the backing store never exceeds the screen.
final class CanvasScrollView: UIScrollView, UIScrollViewDelegate {
    let doc: PaintDocument
    private var activeTouch: UITouch?

    init(doc: PaintDocument) {
        self.doc = doc
        super.init(frame: .zero)
        delegate = self
        backgroundColor = UIColor(cgColor: CanvasColors.workspace)
        contentMode = .redraw
        delaysContentTouches = false
        canCancelContentTouches = true
        isMultipleTouchEnabled = true
        panGestureRecognizer.minimumNumberOfTouches = 2
        panGestureRecognizer.allowedScrollTypesMask = .all
        addGestureRecognizer(UIPinchGestureRecognizer(target: self, action: #selector(pinched(_:))))
        addInteraction(UIPointerInteraction(delegate: nil))
    }

    @available(*, unavailable) required init?(coder: NSCoder) { fatalError() }

    override var canBecomeFirstResponder: Bool { true }

    override func draw(_ rect: CGRect) {
        guard let ctx = UIGraphicsGetCurrentContext() else { return }
        CanvasRenderer.draw(doc, in: ctx, dirty: rect)
    }

    func scrollViewDidScroll(_ scrollView: UIScrollView) { setNeedsDisplay() }

    override func layoutSubviews() {
        super.layoutSubviews()
        setNeedsDisplay()
    }

    @objc private func pinched(_ g: UIPinchGestureRecognizer) {
        guard g.state == .ended else { return }
        let levels = Options.zoomLevels
        let i = levels.firstIndex(of: doc.zoom) ?? 0
        if g.scale > 1.3, i + 1 < levels.count {
            doc.pendingScrollCenter = CanvasGeometry.imagePoint(g.location(in: self), zoom: doc.zoom)
            doc.setZoom(levels[i + 1])
        } else if g.scale < 0.77, i > 0 {
            doc.setZoom(levels[i - 1])
        }
    }

    private func imagePoint(_ t: UITouch) -> CGPoint { CanvasGeometry.imagePoint(t.location(in: self), zoom: doc.zoom) }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard activeTouch == nil, let t = touches.first, (event?.allTouches?.count ?? 1) == 1 else { return }
        becomeFirstResponder()
        activeTouch = t
        let mods = event?.modifierFlags ?? []
        let secondary = event?.buttonMask.contains(.secondary) ?? false
        let slop: CGFloat = t.type == .direct ? 10 : 3
        let handle = CanvasGeometry.handle(at: t.location(in: self), size: doc.canvasSize, zoom: doc.zoom, slop: slop)
        doc.pointerDown(imagePoint(t), handle: handle, button: secondary ? .secondary : .primary,
                        shift: mods.contains(.shift), duplicate: mods.contains(.control) || mods.contains(.alternate),
                        clickCount: t.tapCount)
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let t = activeTouch, touches.contains(t) else { return }
        let points = event?.coalescedTouches(for: t) ?? [t]
        for c in points { doc.pointerMoved(imagePoint(c), shift: event?.modifierFlags.contains(.shift) ?? false) }
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let t = activeTouch, touches.contains(t) else { return }
        activeTouch = nil
        doc.pointerUp(imagePoint(t), shift: event?.modifierFlags.contains(.shift) ?? false, clickCount: t.tapCount)
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let t = activeTouch, touches.contains(t) else { return }
        activeTouch = nil
        doc.pointerCancelled()
    }

    override func pressesBegan(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        switch presses.first?.key?.keyCode {
        case .keyboardDeleteOrBackspace, .keyboardDeleteForward: doc.deleteSelection()
        case .keyboardEscape: doc.cancel()
        default: super.pressesBegan(presses, with: event)
        }
    }
}

struct CanvasHost: UIViewRepresentable {
    @ObservedObject var doc: PaintDocument

    func makeUIView(context: Context) -> CanvasScrollView {
        let view = CanvasScrollView(doc: doc)
        doc.onCanvasChange = { [weak view] in view?.setNeedsDisplay() }
        return view
    }

    func updateUIView(_ view: CanvasScrollView, context: Context) {
        let size = CanvasGeometry.contentSize(doc.canvasSize, zoom: doc.zoom)
        if view.contentSize != size { view.contentSize = size }
        view.setNeedsDisplay()
        if let c = doc.pendingScrollCenter {
            DispatchQueue.main.async {
                let z = CGFloat(doc.zoom), b = view.bounds.size
                let maxX = max(0, size.width - b.width), maxY = max(0, size.height - b.height)
                view.setContentOffset(CGPoint(x: min(maxX, max(0, CanvasGeometry.inset + c.x * z - b.width / 2)),
                                              y: min(maxY, max(0, CanvasGeometry.inset + c.y * z - b.height / 2))),
                                      animated: false)
                doc.pendingScrollCenter = nil
            }
        }
    }
}
#endif

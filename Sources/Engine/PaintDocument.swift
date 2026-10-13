import Combine
import CoreGraphics
import CoreText
import Foundation
import UniformTypeIdentifiers

enum PointerButton { case primary, secondary }

enum ResizeHandle { case right, bottom, corner }

/// A floating or marked region of the picture.
struct Selection {
    var content: Bitmap
    /// Non-zero pixels are inside the selection (free-form only).
    var mask: Bitmap?
    var origin: IntPoint
    /// Whether the content has been cut out of the picture yet.
    var lifted: Bool

    var rect: IntRect { IntRect(x: origin.x, y: origin.y, width: content.width, height: content.height) }
}

enum DialogKind: Identifiable {
    case attributes, flipRotate, stretchSkew, customZoom, editColors, about, helpTopics
    case confirmNew
    case message(String)

    var id: String { "\(self)" }
}

/// A text box being typed into on the canvas.
struct TextBox {
    var rect: IntRect
    var text = ""
    var selection = NSRange(location: 0, length: 0)
    /// The picture under the box before any text was typed.
    var base: Bitmap
}

/// The platform's hidden text view that receives keystrokes for the text tool.
@MainActor
protocol TextInputBridge: AnyObject {
    /// Starts a fresh, empty edit and takes keyboard focus.
    func beginTextEditing()
    /// Takes keyboard focus back without changing the text.
    func focusText()
    func endTextEditing()
    func setTextSelection(_ range: NSRange)
}

/// What a pointer is over on an open text box.
enum TextBoxHit: Equatable {
    case inside
    /// The dashed border: drag to move the box.
    case border
    /// A sizing handle; each flag says which edges follow the pointer.
    case handle(left: Bool, top: Bool, right: Bool, bottom: Bool)
}

enum ImportMode { case open, pasteFrom }
enum ExportMode { case saveAs, copyTo }

/// Fast-changing status bar values live apart so they don't re-render the whole window.
@MainActor
final class StatusModel: ObservableObject {
    @Published var cursor: IntPoint?
    @Published var extent: IntSize?
}

@MainActor
final class PaintDocument: ObservableObject {
    // MARK: Picture

    private(set) var image = Bitmap(width: 640, height: 480)
    private(set) var selection: Selection? {
        didSet { if (oldValue == nil) != (selection == nil) { hasSelection = selection != nil } }
    }
    /// Rubber-band overlays drawn by the canvas, in image pixels.
    private(set) var marquee: IntRect?
    private(set) var lassoPoints: [IntPoint] = []
    private(set) var resizePreview: IntSize?

    /// Called whenever the canvas needs to repaint.
    var onCanvasChange: (() -> Void)?
    private var cachedImage: CGImage?

    let status = StatusModel()

    // MARK: Published UI state

    @Published private(set) var canvasSize = IntSize(width: 640, height: 480)
    @Published private(set) var hasSelection = false
    @Published private(set) var canUndo = false
    @Published private(set) var canRedo = false
    @Published private(set) var isDirty = false

    @Published var tool: Tool = .pencil {
        didSet { if oldValue != tool { toolDidChange(from: oldValue) } }
    }
    @Published var primary = RGBA.black { didSet { if textBox != nil { renderTextBox() } } }
    @Published var secondary = RGBA.white { didSet { if textBox != nil { renderTextBox() } } }
    @Published var palette = Palette.standard
    @Published var selectedPaletteIndex = 0

    @Published var lineWidth = 1
    @Published var brushShape = BrushShape.circleMedium
    @Published var eraserSize = 8
    @Published var airbrushSize = 9
    @Published var fillStyle = FillStyle.outline
    @Published var transparentSelection = false { didSet { if textBox != nil { renderTextBox() } else { refresh() } } }

    // Text tool
    private(set) var textBox: TextBox?
    @Published private(set) var isEditingText = false
    @Published var textStyle = TextLayout.Style() { didSet { if textBox != nil { renderTextBox(); textInput?.focusText() } } }
    @Published var showTextToolbar = true
    weak var textInput: TextInputBridge?
    private(set) var caretVisible = true
    private var caretTimer: Timer?
    private var textClickCommits = false

    @Published var zoom = 1
    @Published var showGrid = false { didSet { refresh() } }
    @Published var showToolBox = true
    @Published var showColorBox = true
    @Published var showStatusBar = true
    @Published var showThumbnail = false
    @Published var viewingBitmap = false

    @Published var dialog: DialogKind?
    @Published var importMode: ImportMode?
    @Published var exportMode: ExportMode?
    /// Start a new picture once a Save As triggered by "Save changes?" completes.
    private var newAfterSave = false
    /// Image point the canvas should scroll to centre, then clear.
    @Published var pendingScrollCenter: CGPoint?

    @Published var fileName = "untitled"
    private(set) var fileURL: URL?

    private var previousTool: Tool = .pencil
    private var undoStack: [Bitmap] = []
    private var redoStack: [Bitmap] = []

    // MARK: Gesture state

    private enum Gesture {
        case none
        case freehand(last: IntPoint, button: PointerButton)
        case shape(start: IntPoint, base: Bitmap, button: PointerButton)
        case marquee(start: IntPoint)
        case lasso
        case moveSelection(grab: IntPoint)
        case textSelect(anchor: Int)
        case textMove(grab: CGPoint, start: IntRect)
        case textResize(TextBoxHit, from: CGPoint, start: IntRect)
        case resize(ResizeHandle)
        case polygon
        case curve
        case airbrush(button: PointerButton)
        case picker(button: PointerButton)
    }

    private struct PolygonDraft {
        var points: [IntPoint]
        var base: Bitmap
        var fg: Pixel
        var bg: Pixel
    }

    private struct CurveDraft {
        var stage: Int
        var start: IntPoint, end: IntPoint, c1: IntPoint, c2: IntPoint
        var base: Bitmap
        var color: Pixel
    }

    private var gesture = Gesture.none
    private var polygon: PolygonDraft?
    private var curve: CurveDraft?
    private var airbrushPoint = IntPoint.zero
    private var airbrushTimer: Timer?

    // MARK: Rendering support

    func refresh() {
        cachedImage = nil
        if canvasSize != image.size { canvasSize = image.size }
        onCanvasChange?()
    }

    var cgImage: CGImage? {
        if cachedImage == nil { cachedImage = image.makeCGImage() }
        return cachedImage
    }

    func selectionImage() -> CGImage? {
        guard let s = selection, s.lifted else { return nil }
        return s.content.makeCGImage(transparent: transparentSelection ? secondary.pixel : nil, mask: s.mask)
    }

    // MARK: Undo

    private func pushUndo() {
        undoStack.append(image)
        if undoStack.count > 50 { undoStack.removeFirst() }
        redoStack.removeAll()
        isDirty = true
        updateUndoFlags()
    }

    /// Drops the snapshot taken for an action that was then abandoned.
    private func discardLastUndo(restore: Bool) {
        guard let last = undoStack.popLast() else { return }
        if restore { image = last }
        updateUndoFlags()
    }

    private func updateUndoFlags() {
        canUndo = !undoStack.isEmpty
        canRedo = !redoStack.isEmpty
    }

    func undo() {
        commitText()
        if polygon != nil || curve != nil { cancelDrafts(); return }
        selection = nil
        guard let prev = undoStack.popLast() else { refresh(); return }
        redoStack.append(image)
        image = prev
        isDirty = true
        updateUndoFlags()
        refresh()
    }

    func redo() {
        finishDrafts()
        commitSelection()
        guard let next = redoStack.popLast() else { return }
        undoStack.append(image)
        image = next
        updateUndoFlags()
        refresh()
    }

    // MARK: Tool changes

    private func toolDidChange(from old: Tool) {
        if old != .picker { previousTool = old }
        finishDrafts()
        commitSelection()
        refresh()
    }

    func color(for button: PointerButton) -> RGBA { button == .primary ? primary : secondary }
    private func other(_ button: PointerButton) -> PointerButton { button == .primary ? .secondary : .primary }

    // MARK: Pointer input (image coordinates)

    func pointerDown(_ p: CGPoint, handle: ResizeHandle?, button: PointerButton, shift: Bool, duplicate: Bool, clickCount: Int) {
        let ip = IntPoint(Int(floor(p.x)), Int(floor(p.y)))
        if let handle {
            finishDrafts()
            commitSelection()
            gesture = .resize(handle)
            resizePreview = image.size
            status.extent = image.size
            return
        }
        let fg = color(for: button).pixel

        switch tool {
        case .pencil:
            pushUndo()
            image.set(ip.x, ip.y, fg)
            gesture = .freehand(last: ip, button: button)
        case .brush:
            pushUndo()
            image.stamp(brushShape.offsets, at: ip.x, ip.y, fg)
            gesture = .freehand(last: ip, button: button)
        case .eraser:
            pushUndo()
            erase(from: ip, to: ip, button: button)
            gesture = .freehand(last: ip, button: button)
        case .airbrush:
            pushUndo()
            airbrushPoint = ip
            spray(color: fg)
            gesture = .airbrush(button: button)
            airbrushTimer = Timer.scheduledTimer(withTimeInterval: 0.03, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated {
                    guard let self, case .airbrush(let b) = self.gesture else { return }
                    self.spray(color: self.color(for: b).pixel)
                    self.refresh()
                }
            }
        case .fill:
            pushUndo()
            image.floodFill(from: ip.x, ip.y, with: fg)
        case .picker:
            pick(at: ip, button: button)
            gesture = .picker(button: button)
        case .magnifier:
            if zoom == 1 {
                zoom = 4
                pendingScrollCenter = p
            } else {
                zoom = 1
            }
        case .line, .rectangle, .ellipse, .roundedRectangle:
            pushUndo()
            gesture = .shape(start: ip, base: image, button: button)
            renderShape(from: ip, to: ip, button: button)
        case .text:
            if let box = textBox, let hit = textBoxHit(at: p) {
                switch hit {
                case .border:
                    gesture = .textMove(grab: CGPoint(x: p.x - CGFloat(box.rect.x), y: p.y - CGFloat(box.rect.y)), start: box.rect)
                case .handle:
                    gesture = .textResize(hit, from: p, start: box.rect)
                case .inside:
                    let idx = textIndex(at: p)
                    setTextSelection(NSRange(location: idx, length: 0))
                    gesture = .textSelect(anchor: idx)
                }
            } else {
                // As in XP, a click outside an open box only finishes it; a drag still starts a new one.
                textClickCommits = textBox != nil
                commitText()
                commitSelection()
                marquee = IntRect(corner: ip, ip)
                gesture = .marquee(start: ip)
            }
        case .rectSelect, .freeSelect:
            if let s = selection, s.rect.contains(ip) {
                beginMove(at: ip, duplicate: duplicate)
            } else {
                commitSelection()
                if tool == .freeSelect {
                    lassoPoints = [ip]
                    gesture = .lasso
                } else {
                    marquee = IntRect(corner: ip, ip)
                    gesture = .marquee(start: ip)
                }
            }
        case .polygon:
            if var d = polygon {
                let last = d.points.last ?? ip
                d.points.append(shift ? constrainLine(ip, from: last) : ip)
                polygon = d
            } else {
                pushUndo()
                polygon = PolygonDraft(points: [ip, ip], base: image, fg: fg, bg: color(for: other(button)).pixel)
            }
            drawPolygonDraft(closed: false)
            gesture = .polygon
        case .curve:
            if var c = curve {
                if c.stage == 1 { c.c1 = ip; c.c2 = ip } else { c.c2 = ip }
                curve = c
            } else {
                pushUndo()
                curve = CurveDraft(stage: 0, start: ip, end: ip, c1: ip, c2: ip, base: image, color: fg)
            }
            drawCurveDraft()
            gesture = .curve
        }
        refresh()
    }

    func pointerMoved(_ p: CGPoint, shift: Bool) {
        let ip = IntPoint(Int(floor(p.x)), Int(floor(p.y)))
        hover(p)

        switch gesture {
        case .none:
            return
        case .freehand(let last, let button):
            let fg = color(for: button).pixel
            switch tool {
            case .pencil: image.drawLine(last, ip, offsets: [.zero], color: fg)
            case .brush: image.drawLine(last, ip, offsets: brushShape.offsets, color: fg)
            case .eraser: erase(from: last, to: ip, button: button)
            default: break
            }
            gesture = .freehand(last: ip, button: button)
        case .airbrush(let button):
            airbrushPoint = ip
            spray(color: color(for: button).pixel)
        case .picker(let button):
            pick(at: ip, button: button)
        case .shape(let start, let base, let button):
            image = base
            let end: IntPoint
            if shift { end = tool == .line ? constrainLine(ip, from: start) : constrainSquare(ip, from: start) } else { end = ip }
            renderShape(from: start, to: end, button: button)
            status.extent = IntSize(width: end.x - start.x, height: end.y - start.y)
        case .textSelect(let anchor):
            let idx = textIndex(at: p)
            setTextSelection(NSRange(location: min(anchor, idx), length: abs(idx - anchor)))
        case .textMove(let grab, let start):
            var r = start
            r.x = min(max(0, Int((p.x - grab.x).rounded())), image.width - r.width)
            r.y = min(max(0, Int((p.y - grab.y).rounded())), image.height - r.height)
            moveTextBox(to: r)
        case .textResize(let hit, let from, let start):
            guard case .handle(let left, let top, let right, let bottom) = hit else { break }
            let dx = Int((p.x - from.x).rounded()), dy = Int((p.y - from.y).rounded())
            var x0 = start.x, y0 = start.y, x1 = start.maxX, y1 = start.maxY
            let minSize = 12
            if left { x0 = min(max(0, x0 + dx), x1 - minSize) }
            if right { x1 = max(min(image.width, x1 + dx), x0 + minSize) }
            if top { y0 = min(max(0, y0 + dy), y1 - minSize) }
            if bottom { y1 = max(min(image.height, y1 + dy), y0 + minSize) }
            moveTextBox(to: IntRect(x: x0, y: y0, width: x1 - x0, height: y1 - y0))
            status.extent = IntSize(width: x1 - x0, height: y1 - y0)
        case .marquee(let start):
            let r = IntRect(corner: start, ip)
            marquee = r
            status.extent = IntSize(width: r.width, height: r.height)
        case .lasso:
            if lassoPoints.last != ip { lassoPoints.append(ip) }
        case .moveSelection(let grab):
            selection?.origin = ip - grab
        case .resize(let h):
            var s = image.size
            if h != .bottom { s.width = max(1, ip.x) }
            if h != .right { s.height = max(1, ip.y) }
            resizePreview = s
            status.extent = s
        case .polygon:
            guard var d = polygon, d.points.count >= 2 else { return }
            let anchor = d.points[d.points.count - 2]
            d.points[d.points.count - 1] = shift ? constrainLine(ip, from: anchor) : ip
            polygon = d
            drawPolygonDraft(closed: false)
        case .curve:
            guard var c = curve else { return }
            switch c.stage {
            case 0: c.end = shift ? constrainLine(ip, from: c.start) : ip
            case 1: c.c1 = ip; c.c2 = ip
            default: c.c2 = ip
            }
            curve = c
            drawCurveDraft()
        }
        refresh()
    }

    func pointerUp(_ p: CGPoint, shift: Bool, clickCount: Int) {
        pointerMoved(p, shift: shift)
        let ip = IntPoint(Int(floor(p.x)), Int(floor(p.y)))

        switch gesture {
        case .airbrush:
            airbrushTimer?.invalidate()
            airbrushTimer = nil
        case .picker:
            tool = previousTool
        case .marquee(let start):
            marquee = nil
            let r = IntRect(corner: start, ip).intersection(image.bounds)
            if tool == .text {
                // A plain click gets a one-line box, which grows as you type.
                let dragged = r.width > 8 && r.height > 8
                let box = dragged ? r
                    : IntRect(x: start.x, y: start.y, width: 160,
                              height: TextLayout.fittingHeight(text: "", style: textStyle, width: 160)).intersection(image.bounds)
                if !box.isEmpty && (dragged || !textClickCommits) { beginText(in: box) }
            } else if !r.isEmpty && (r.width > 1 || r.height > 1) {
                selection = Selection(content: image.cropped(to: r, fill: secondary.pixel), mask: nil, origin: r.origin, lifted: false)
            }
        case .lasso:
            makeFreeFormSelection(lassoPoints)
            lassoPoints = []
        case .resize:
            if let s = resizePreview, s != image.size {
                pushUndo()
                image = image.resizedCanvas(width: s.width, height: s.height, fill: secondary.pixel)
            }
            resizePreview = nil
        case .polygon:
            if var d = polygon {
                let closesShape = d.points.count > 3 && abs(ip.x - d.points[0].x) <= 3 && abs(ip.y - d.points[0].y) <= 3
                if clickCount >= 2 || closesShape {
                    if closesShape { d.points.removeLast() }
                    polygon = d
                    finishPolygon()
                }
            }
        case .curve:
            if var c = curve {
                c.stage += 1
                curve = c
                if c.stage > 2 { curve = nil }
            }
        default:
            break
        }
        gesture = .none
        status.extent = nil
        refresh()
    }

    /// The touch was taken over by a scroll/zoom gesture; abandon what it started.
    func pointerCancelled() {
        switch gesture {
        case .freehand, .shape, .airbrush:
            airbrushTimer?.invalidate()
            airbrushTimer = nil
            discardLastUndo(restore: true)
        case .polygon, .curve:
            cancelDrafts()
        default:
            break
        }
        marquee = nil
        lassoPoints = []
        resizePreview = nil
        gesture = .none
        refresh()
    }

    func hover(_ p: CGPoint?) {
        guard let p else { status.cursor = nil; return }
        let ip = IntPoint(Int(floor(p.x)), Int(floor(p.y)))
        status.cursor = image.contains(ip.x, ip.y) ? ip : nil
    }

    // MARK: Tool helpers

    private func pick(at ip: IntPoint, button: PointerButton) {
        guard image.contains(ip.x, ip.y) else { return }
        let c = RGBA(pixel: image.pixel(ip.x, ip.y))
        if button == .primary { primary = c } else { secondary = c }
    }

    private func erase(from a: IntPoint, to b: IntPoint, button: PointerButton) {
        let pen = Bitmap.squareOffsets(eraserSize)
        if button == .primary {
            image.drawLine(a, b, offsets: pen, color: secondary.pixel)
        } else {
            // Color eraser: only replaces the foreground color.
            let target = primary.pixel, replacement = secondary.pixel
            Bitmap.forEachLinePoint(a, b) { x, y in
                for o in pen {
                    let px = x + o.x, py = y + o.y
                    if image.contains(px, py) && image.pixel(px, py) == target { image.set(px, py, replacement) }
                }
            }
        }
    }

    private func spray(color: Pixel) {
        let r = Double(airbrushSize) / 2
        for _ in 0..<(airbrushSize / 2 + 2) {
            let a = Double.random(in: 0..<(2 * .pi)), d = Double.random(in: 0...r)
            image.set(airbrushPoint.x + Int((cos(a) * d).rounded()), airbrushPoint.y + Int((sin(a) * d).rounded()), color)
        }
    }

    private func shapeColors(fg: Pixel, bg: Pixel) -> (stroke: Pixel?, fill: Pixel?) {
        switch fillStyle {
        case .outline: (fg, nil)
        case .outlineFill: (fg, bg)
        case .fillOnly: (nil, fg)
        }
    }

    private func renderShape(from start: IntPoint, to end: IntPoint, button: PointerButton) {
        let fg = color(for: button).pixel, bg = color(for: other(button)).pixel
        let kind: Bitmap.ShapeKind
        switch tool {
        case .line:
            image.drawLine(start, end, offsets: Bitmap.penOffsets(width: lineWidth), color: fg)
            return
        case .ellipse: kind = .ellipse
        case .roundedRectangle: kind = .roundedRectangle
        default: kind = .rectangle
        }
        let c = shapeColors(fg: fg, bg: bg)
        image.drawShape(kind, in: IntRect(corner: start, end), lineWidth: lineWidth, stroke: c.stroke, fill: c.fill)
    }

    private func constrainSquare(_ p: IntPoint, from s: IntPoint) -> IntPoint {
        let dx = p.x - s.x, dy = p.y - s.y, m = max(abs(dx), abs(dy))
        return IntPoint(s.x + (dx < 0 ? -m : m), s.y + (dy < 0 ? -m : m))
    }

    /// Snaps to horizontal, vertical or 45°.
    private func constrainLine(_ p: IntPoint, from s: IntPoint) -> IntPoint {
        let dx = p.x - s.x, dy = p.y - s.y
        if abs(dx) > abs(dy) * 2 { return IntPoint(p.x, s.y) }
        if abs(dy) > abs(dx) * 2 { return IntPoint(s.x, p.y) }
        return constrainSquare(p, from: s)
    }

    // MARK: Polygon and curve drafts

    private func drawPolygonDraft(closed: Bool) {
        guard let d = polygon else { return }
        image = d.base
        if closed {
            let c = shapeColors(fg: d.fg, bg: d.bg)
            image.drawPolygon(d.points, lineWidth: lineWidth, stroke: c.stroke, fill: c.fill)
        } else {
            let pen = Bitmap.penOffsets(width: lineWidth)
            for i in 1..<d.points.count { image.drawLine(d.points[i - 1], d.points[i], offsets: pen, color: d.fg) }
        }
    }

    private func finishPolygon() {
        guard var d = polygon else { return }
        var pts: [IntPoint] = []
        for p in d.points where pts.last != p { pts.append(p) }
        d.points = pts
        polygon = d
        if pts.count >= 3 { drawPolygonDraft(closed: true) }
        polygon = nil
    }

    private func drawCurveDraft() {
        guard let c = curve else { return }
        image = c.base
        let pen = Bitmap.penOffsets(width: lineWidth)
        if c.stage == 0 {
            image.drawLine(c.start, c.end, offsets: pen, color: c.color)
            return
        }
        func dist(_ a: IntPoint, _ b: IntPoint) -> Double { hypot(Double(a.x - b.x), Double(a.y - b.y)) }
        let steps = max(8, Int((dist(c.start, c.c1) + dist(c.c1, c.c2) + dist(c.c2, c.end)) / 2))
        var prev = c.start
        for i in 1...steps {
            let t = Double(i) / Double(steps), u = 1 - t
            let b0 = u * u * u, b1 = 3 * u * u * t, b2 = 3 * u * t * t, b3 = t * t * t
            let x = b0 * Double(c.start.x) + b1 * Double(c.c1.x) + b2 * Double(c.c2.x) + b3 * Double(c.end.x)
            let y = b0 * Double(c.start.y) + b1 * Double(c.c1.y) + b2 * Double(c.c2.y) + b3 * Double(c.end.y)
            let p = IntPoint(Int(x.rounded()), Int(y.rounded()))
            image.drawLine(prev, p, offsets: pen, color: c.color)
            prev = p
        }
    }

    /// Accepts any half-drawn polygon or curve as it stands.
    func finishDrafts() {
        commitText()
        if polygon != nil { finishPolygon() }
        curve = nil
    }

    func cancelDrafts() {
        if let d = polygon { image = d.base; polygon = nil; discardLastUndo(restore: false) }
        if let c = curve { image = c.base; curve = nil; discardLastUndo(restore: false) }
        refresh()
    }

    func cancel() {
        if textBox != nil { commitText(); return }
        if polygon != nil || curve != nil { cancelDrafts(); return }
        commitSelection()
        refresh()
    }

    // MARK: Selection

    private func makeFreeFormSelection(_ pts: [IntPoint]) {
        guard pts.count >= 3 else { return }
        let xs = pts.map(\.x), ys = pts.map(\.y)
        let r = IntRect(corner: IntPoint(xs.min()!, ys.min()!), IntPoint(xs.max()!, ys.max()!)).intersection(image.bounds)
        guard !r.isEmpty else { return }
        var mask = Bitmap(width: r.width, height: r.height, fill: 0)
        let local = pts.map { $0 - r.origin }
        mask.drawPolygon(local, lineWidth: 1, stroke: 1, fill: 1)
        selection = Selection(content: image.cropped(to: r, fill: secondary.pixel), mask: mask, origin: r.origin, lifted: false)
    }

    private func clearUnder(_ s: Selection) {
        let bg = secondary.pixel
        for y in 0..<s.content.height {
            for x in 0..<s.content.width where s.mask == nil || s.mask!.pixels[y * s.content.width + x] != 0 {
                image.set(s.origin.x + x, s.origin.y + y, bg)
            }
        }
    }

    private func beginMove(at ip: IntPoint, duplicate: Bool) {
        guard var s = selection else { return }
        if !s.lifted {
            pushUndo()
            if !duplicate { clearUnder(s) }
            s.lifted = true
        } else if duplicate {
            pushUndo()
            stamp(s)
        }
        selection = s
        gesture = .moveSelection(grab: ip - s.origin)
    }

    private func stamp(_ s: Selection) {
        image.draw(s.content, at: s.origin, transparent: transparentSelection ? secondary.pixel : nil, mask: s.mask)
    }

    private func liftSelection() {
        guard var s = selection, !s.lifted else { return }
        pushUndo()
        clearUnder(s)
        s.lifted = true
        selection = s
    }

    func commitSelection() {
        guard let s = selection else { return }
        selection = nil
        if s.lifted { stamp(s) }
        refresh()
    }

    /// Selection contents with anything outside a free-form outline in the background color.
    private func flattened(_ s: Selection) -> Bitmap {
        guard let mask = s.mask else { return s.content }
        var out = s.content
        for i in out.pixels.indices where mask.pixels[i] == 0 { out.pixels[i] = secondary.pixel }
        return out
    }

    func selectAll() {
        tool = .rectSelect
        finishDrafts()
        commitSelection()
        selection = Selection(content: image, mask: nil, origin: .zero, lifted: false)
        refresh()
    }

    func deleteSelection() {
        guard let s = selection else { return }
        if !s.lifted { pushUndo(); clearUnder(s) }
        selection = nil
        refresh()
    }

    func copy() {
        guard let s = selection else { return }
        Clipboard.write(flattened(s))
    }

    func cut() {
        copy()
        deleteSelection()
    }

    func paste() {
        guard let b = Clipboard.read() else { return }
        insertFloating(b)
    }

    func insertFloating(_ b: Bitmap) {
        tool = .rectSelect
        finishDrafts()
        commitSelection()
        pushUndo()
        if b.width > image.width || b.height > image.height {
            image = image.resizedCanvas(width: max(b.width, image.width), height: max(b.height, image.height), fill: secondary.pixel)
        }
        selection = Selection(content: b, mask: nil, origin: .zero, lifted: true)
        refresh()
    }

    var selectionBitmap: Bitmap? { selection.map(flattened) }

    // MARK: Image menu

    private func transform(geometric: Bool, _ f: (Bitmap, Pixel) -> Bitmap) {
        finishDrafts()
        if selection != nil {
            liftSelection()
            guard var s = selection else { return }
            s.content = f(s.content, secondary.pixel)
            if geometric { s.mask = s.mask.map { f($0, 0) } }
            selection = s
        } else {
            pushUndo()
            image = f(image, secondary.pixel)
        }
        refresh()
    }

    func flip(horizontal: Bool) {
        transform(geometric: true) { b, _ in horizontal ? b.flippedHorizontally() : b.flippedVertically() }
    }

    func rotate(quarterTurns: Int) {
        transform(geometric: true) { b, _ in b.rotated(quarterTurns: quarterTurns) }
    }

    func stretchSkew(horizontalPercent: Int, verticalPercent: Int, horizontalSkew: Double, verticalSkew: Double) {
        transform(geometric: true) { b, fill in
            var out = b
            if horizontalPercent != 100 || verticalPercent != 100 {
                out = out.scaled(toWidth: max(1, b.width * horizontalPercent / 100), height: max(1, b.height * verticalPercent / 100))
            }
            if horizontalSkew != 0 || verticalSkew != 0 {
                out = out.skewed(horizontalDegrees: horizontalSkew, verticalDegrees: verticalSkew, fill: fill)
            }
            return out
        }
    }

    func invertColors() {
        transform(geometric: false) { b, _ in b.inverted() }
    }

    func clearImage() {
        finishDrafts()
        if selection != nil { deleteSelection(); return }
        pushUndo()
        image = Bitmap(width: image.width, height: image.height, fill: secondary.pixel)
        refresh()
    }

    func setAttributes(width: Int, height: Int) {
        finishDrafts()
        commitSelection()
        guard width != image.width || height != image.height else { return }
        pushUndo()
        image = image.resizedCanvas(width: width, height: height, fill: secondary.pixel)
        refresh()
    }

    // MARK: Text

    private func beginText(in rect: IntRect) {
        pushUndo()
        textBox = TextBox(rect: rect, base: image)
        isEditingText = true
        renderTextBox()
        textInput?.beginTextEditing()
        caretVisible = true
        caretTimer = Timer.scheduledTimer(withTimeInterval: 0.53, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, self.textBox != nil else { return }
                self.caretVisible.toggle()
                self.onCanvasChange?()
            }
        }
    }

    /// Bakes the typed text into the picture and closes the box.
    func commitText() {
        guard let box = textBox else { return }
        caretTimer?.invalidate()
        caretTimer = nil
        textBox = nil
        isEditingText = false
        if box.text.isEmpty { discardLastUndo(restore: true) }
        textInput?.endTextEditing()
        refresh()
    }

    private func layout(for box: TextBox) -> TextLayout {
        TextLayout(text: box.text, style: textStyle, color: primary,
                   size: CGSize(width: box.rect.width, height: box.rect.height))
    }

    /// Redraws the box's text over its saved background, growing the box downward to fit.
    private func renderTextBox() {
        guard var box = textBox else { return }
        let needed = TextLayout.fittingHeight(text: box.text, style: textStyle, width: CGFloat(box.rect.width))
        if needed > box.rect.height { box.rect.height = min(needed, image.height - box.rect.y) }
        textBox = box
        image = box.base
        if !transparentSelection { image.fill(box.rect, secondary.pixel) }
        image.drawText(layout(for: box), at: box.rect.origin)
        refresh()
    }

    /// Called by the platform text view as the user types.
    func textDidChange(_ text: String, selection: NSRange) {
        guard textBox != nil else { return }
        textBox?.text = text
        textBox?.selection = selection
        isDirty = true
        caretVisible = true
        renderTextBox()
    }

    func textSelectionDidChange(_ selection: NSRange) {
        guard textBox != nil else { return }
        textBox?.selection = selection
        caretVisible = true
        onCanvasChange?()
    }

    private func setTextSelection(_ range: NSRange) {
        textBox?.selection = range
        textInput?.setTextSelection(range)
        caretVisible = true
        refresh()
    }

    private func textIndex(at p: CGPoint) -> Int {
        guard let box = textBox else { return 0 }
        return layout(for: box).index(at: CGPoint(x: p.x - CGFloat(box.rect.x), y: p.y - CGFloat(box.rect.y)))
    }

    private func moveTextBox(to r: IntRect) {
        guard textBox != nil else { return }
        textBox?.rect = r
        renderTextBox()
        textInput?.focusText()
    }

    /// Distance, in view points, within which the pointer catches a border or handle.
    var pointerSlop: CGFloat = 4

    /// Handle centres around a text box, in image pixels, with the edges each one drags.
    static func textHandles(_ r: IntRect) -> [(CGPoint, TextBoxHit)] {
        let x0 = CGFloat(r.x), y0 = CGFloat(r.y), x1 = CGFloat(r.maxX), y1 = CGFloat(r.maxY)
        let mx = (x0 + x1) / 2, my = (y0 + y1) / 2
        return [
            (CGPoint(x: x0, y: y0), .handle(left: true, top: true, right: false, bottom: false)),
            (CGPoint(x: mx, y: y0), .handle(left: false, top: true, right: false, bottom: false)),
            (CGPoint(x: x1, y: y0), .handle(left: false, top: true, right: true, bottom: false)),
            (CGPoint(x: x1, y: my), .handle(left: false, top: false, right: true, bottom: false)),
            (CGPoint(x: x1, y: y1), .handle(left: false, top: false, right: true, bottom: true)),
            (CGPoint(x: mx, y: y1), .handle(left: false, top: false, right: false, bottom: true)),
            (CGPoint(x: x0, y: y1), .handle(left: true, top: false, right: false, bottom: true)),
            (CGPoint(x: x0, y: my), .handle(left: true, top: false, right: false, bottom: false)),
        ]
    }

    /// What part of the open text box, if any, is under an image point.
    func textBoxHit(at p: CGPoint) -> TextBoxHit? {
        guard let box = textBox else { return nil }
        let slop = max(pointerSlop, 3) / CGFloat(zoom) + 1
        for (c, hit) in Self.textHandles(box.rect) where abs(p.x - c.x) <= slop + 1 && abs(p.y - c.y) <= slop + 1 {
            return hit
        }
        let r = CGRect(x: box.rect.x, y: box.rect.y, width: box.rect.width, height: box.rect.height)
        if r.insetBy(dx: slop / 2, dy: slop / 2).contains(p) { return .inside }
        if r.insetBy(dx: -slop, dy: -slop).contains(p) { return .border }
        return nil
    }

    /// Caret and selection highlight for the canvas overlay, in image pixels.
    func textOverlay() -> (box: IntRect, caret: CGRect?, highlights: [CGRect])? {
        guard let box = textBox else { return nil }
        let l = layout(for: box)
        let offset = CGAffineTransform(translationX: CGFloat(box.rect.x), y: CGFloat(box.rect.y))
        let caret = box.selection.length == 0 && caretVisible ? l.caret(at: box.selection.location).applying(offset) : nil
        return (box.rect, caret, l.highlightRects(box.selection).map { $0.applying(offset) })
    }

    // MARK: Colors

    func selectPalette(_ index: Int, button: PointerButton) {
        selectedPaletteIndex = index
        if button == .primary { primary = palette[index] } else { secondary = palette[index] }
    }

    func defineCustomColor(_ c: RGBA) {
        palette[selectedPaletteIndex] = c
        primary = c
    }

    // MARK: Files

    func requestNew() {
        if isDirty { dialog = .confirmNew } else { newImage() }
    }

    func saveThenNew() {
        save()
        if isDirty { newAfterSave = true } else { newImage() }
    }

    func newImage() {
        newAfterSave = false
        load(Bitmap(width: 640, height: 480), url: nil)
    }

    #if DEBUG
    /// Debug builds only: `-demoImage <path>` opens a picture at launch (used for screenshots).
    func loadDemoImageIfRequested() {
        guard let path = UserDefaults.standard.string(forKey: "demoImage"),
              let data = FileManager.default.contents(atPath: path), let b = Bitmap(data: data) else { return }
        load(b, url: nil)
    }
    #endif

    private func load(_ b: Bitmap, url: URL?) {
        airbrushTimer?.invalidate()
        polygon = nil
        curve = nil
        selection = nil
        gesture = .none
        image = b
        undoStack.removeAll()
        redoStack.removeAll()
        updateUndoFlags()
        fileURL = url
        fileName = url?.lastPathComponent ?? "untitled"
        isDirty = false
        zoom = 1
        refresh()
    }

    func handleImport(_ result: Result<URL, Error>, mode: ImportMode) {
        guard case .success(let url) = result else { return }
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        guard let data = try? Data(contentsOf: url), let b = Bitmap(data: data) else {
            dialog = .message("RetroPaint cannot read this file.\nThis is not a valid bitmap file, or its format is not currently supported.")
            return
        }
        switch mode {
        case .open: load(b, url: url)
        case .pasteFrom: insertFloating(b)
        }
    }

    /// The bitmap a Save As / Copy To exporter should write.
    func exportBitmap(for mode: ExportMode) -> Bitmap {
        finishDrafts()
        switch mode {
        case .saveAs: commitSelection(); return image
        case .copyTo: return selectionBitmap ?? image
        }
    }

    func handleExport(_ result: Result<URL, Error>, mode: ExportMode) {
        guard mode == .saveAs, case .success(let url) = result else { newAfterSave = false; return }
        fileURL = url
        fileName = url.lastPathComponent
        isDirty = false
        if newAfterSave { newImage() }
    }

    func save() {
        finishDrafts()
        commitSelection()
        guard let url = fileURL else { exportMode = .saveAs; return }
        let type = UTType(filenameExtension: url.pathExtension) ?? .png
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        guard let data = image.encoded(as: type), (try? data.write(to: url, options: .atomic)) != nil else {
            exportMode = .saveAs
            return
        }
        isDirty = false
    }

    func setZoom(_ z: Int) {
        zoom = max(1, min(8, z))
        refresh()
    }
}

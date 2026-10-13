import CoreGraphics

/// Layout of the picture inside the scrollable workspace, in view points.
enum CanvasGeometry {
    static let inset: CGFloat = 4
    static let handleSize: CGFloat = 5

    static func imageRect(_ size: IntSize, zoom: Int) -> CGRect {
        CGRect(x: inset, y: inset, width: CGFloat(size.width * zoom), height: CGFloat(size.height * zoom))
    }

    static func contentSize(_ size: IntSize, zoom: Int) -> CGSize {
        let r = imageRect(size, zoom: zoom)
        return CGSize(width: r.maxX + inset + handleSize * 2, height: r.maxY + inset + handleSize * 2)
    }

    static func handleRects(_ size: IntSize, zoom: Int) -> [(ResizeHandle, CGRect)] {
        let r = imageRect(size, zoom: zoom), s = handleSize
        return [
            (.right, CGRect(x: r.maxX, y: r.midY - s / 2, width: s, height: s)),
            (.bottom, CGRect(x: r.midX - s / 2, y: r.maxY, width: s, height: s)),
            (.corner, CGRect(x: r.maxX, y: r.maxY, width: s, height: s)),
        ]
    }

    static func handle(at p: CGPoint, size: IntSize, zoom: Int, slop: CGFloat) -> ResizeHandle? {
        handleRects(size, zoom: zoom).first { $0.1.insetBy(dx: -slop, dy: -slop).contains(p) }?.0
    }

    /// View point → fractional image pixel.
    static func imagePoint(_ p: CGPoint, zoom: Int) -> CGPoint {
        CGPoint(x: (p.x - inset) / CGFloat(zoom), y: (p.y - inset) / CGFloat(zoom))
    }
}

enum CanvasColors {
    static let workspace = CGColor(srgbRed: 0.5, green: 0.5, blue: 0.5, alpha: 1)
    static let handle = CGColor(srgbRed: 0, green: 0, blue: 0.5, alpha: 1)
    static let grid = CGColor(srgbRed: 0.5, green: 0.5, blue: 0.5, alpha: 1)
    static let marquee = CGColor(srgbRed: 0, green: 0, blue: 0.5, alpha: 1)
    static let white = CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 1)
    static let black = CGColor(srgbRed: 0, green: 0, blue: 0, alpha: 1)
}

/// Draws the workspace into a top-left-origin context. Shared by the macOS and iOS canvas views.
@MainActor
enum CanvasRenderer {
    static func draw(_ doc: PaintDocument, in ctx: CGContext, dirty: CGRect) {
        let zoom = doc.zoom, z = CGFloat(zoom)
        let size = doc.canvasSize
        let rect = CanvasGeometry.imageRect(size, zoom: zoom)

        ctx.setFillColor(CanvasColors.workspace)
        ctx.fill(dirty)
        ctx.interpolationQuality = .none
        ctx.setShouldAntialias(false)

        if let img = doc.cgImage { drawImage(img, in: rect, ctx) }

        if let sel = doc.selection, let img = doc.selectionImage() {
            let r = CGRect(x: rect.minX + CGFloat(sel.origin.x) * z, y: rect.minY + CGFloat(sel.origin.y) * z,
                           width: CGFloat(sel.content.width) * z, height: CGFloat(sel.content.height) * z)
            ctx.saveGState()
            ctx.clip(to: rect)
            drawImage(img, in: r, ctx)
            ctx.restoreGState()
        }

        if doc.showGrid && zoom >= 4 { drawGrid(rect: rect, zoom: z, dirty: dirty, ctx) }

        func viewRect(_ r: IntRect) -> CGRect {
            CGRect(x: rect.minX + CGFloat(r.x) * z, y: rect.minY + CGFloat(r.y) * z,
                   width: CGFloat(r.width) * z, height: CGFloat(r.height) * z)
        }
        if let sel = doc.selection { dashed(viewRect(sel.rect).insetBy(dx: 0.5, dy: 0.5), ctx) }
        if let m = doc.marquee { dashed(viewRect(m).insetBy(dx: 0.5, dy: 0.5), ctx) }

        if doc.lassoPoints.count > 1 {
            ctx.setStrokeColor(CanvasColors.black)
            ctx.setLineWidth(1)
            ctx.addLines(between: doc.lassoPoints.map {
                CGPoint(x: rect.minX + (CGFloat($0.x) + 0.5) * z, y: rect.minY + (CGFloat($0.y) + 0.5) * z)
            })
            ctx.strokePath()
        }

        if let s = doc.resizePreview {
            dashed(CGRect(x: rect.minX, y: rect.minY, width: CGFloat(s.width) * z, height: CGFloat(s.height) * z)
                .insetBy(dx: 0.5, dy: 0.5), ctx)
        }

        ctx.setFillColor(CanvasColors.handle)
        for (_, r) in CanvasGeometry.handleRects(size, zoom: zoom) { ctx.fill(r) }
    }

    /// CGImage drawing is bottom-up; flip it into the top-left context.
    static func drawImage(_ img: CGImage, in rect: CGRect, _ ctx: CGContext) {
        ctx.saveGState()
        ctx.translateBy(x: rect.minX, y: rect.maxY)
        ctx.scaleBy(x: 1, y: -1)
        ctx.draw(img, in: CGRect(origin: .zero, size: rect.size))
        ctx.restoreGState()
    }

    private static func drawGrid(rect: CGRect, zoom z: CGFloat, dirty: CGRect, _ ctx: CGContext) {
        let area = rect.intersection(dirty)
        guard !area.isNull else { return }
        ctx.setFillColor(CanvasColors.grid)
        var x = rect.minX + (((area.minX - rect.minX) / z).rounded(.down)) * z
        while x <= area.maxX { ctx.fill(CGRect(x: x, y: area.minY, width: 1, height: area.height)); x += z }
        var y = rect.minY + (((area.minY - rect.minY) / z).rounded(.down)) * z
        while y <= area.maxY { ctx.fill(CGRect(x: area.minX, y: y, width: area.width, height: 1)); y += z }
    }

    private static func dashed(_ r: CGRect, _ ctx: CGContext) {
        ctx.saveGState()
        ctx.setLineWidth(1)
        ctx.setStrokeColor(CanvasColors.white)
        ctx.stroke(r)
        ctx.setStrokeColor(CanvasColors.marquee)
        ctx.setLineDash(phase: 0, lengths: [4, 4])
        ctx.stroke(r)
        ctx.restoreGState()
    }
}

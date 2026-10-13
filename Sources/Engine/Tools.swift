import Foundation

enum Tool: Int, CaseIterable, Identifiable {
    case freeSelect, rectSelect, eraser, fill, picker, magnifier, pencil, brush
    case airbrush, text, line, curve, rectangle, polygon, ellipse, roundedRectangle

    var id: Int { rawValue }

    var name: String {
        switch self {
        case .freeSelect: "Free-Form Select"
        case .rectSelect: "Select"
        case .eraser: "Eraser/Color Eraser"
        case .fill: "Fill With Color"
        case .picker: "Pick Color"
        case .magnifier: "Magnifier"
        case .pencil: "Pencil"
        case .brush: "Brush"
        case .airbrush: "Airbrush"
        case .text: "Text"
        case .line: "Line"
        case .curve: "Curve"
        case .rectangle: "Rectangle"
        case .polygon: "Polygon"
        case .ellipse: "Ellipse"
        case .roundedRectangle: "Rounded Rectangle"
        }
    }

    var help: String {
        switch self {
        case .freeSelect: "Selects a free-form part of the picture to move, copy, or edit."
        case .rectSelect: "Selects a rectangular part of the picture to move, copy, or edit."
        case .eraser: "Erases a portion of the picture, using the selected eraser shape."
        case .fill: "Fills an area with the current drawing color."
        case .picker: "Picks up a color from the picture for drawing."
        case .magnifier: "Changes the magnification."
        case .pencil: "Draws a free-form line one pixel wide."
        case .brush: "Draws using a brush with the selected shape and size."
        case .airbrush: "Draws using an airbrush of the selected size."
        case .text: "Inserts text into the picture."
        case .line: "Draws a straight line with the selected line width."
        case .curve: "Draws a curved line with the selected line width."
        case .rectangle: "Draws a rectangle with the selected fill style."
        case .polygon: "Draws a polygon with the selected fill style."
        case .ellipse: "Draws an ellipse with the selected fill style."
        case .roundedRectangle: "Draws a rounded rectangle with the selected fill style."
        }
    }

    var isSelection: Bool { self == .freeSelect || self == .rectSelect }
    var usesLineWidth: Bool { self == .line || self == .curve }
    var usesFillStyle: Bool { [.rectangle, .polygon, .ellipse, .roundedRectangle].contains(self) }
}

enum FillStyle: Int, CaseIterable {
    case outline, outlineFill, fillOnly
}

enum BrushShape: Int, CaseIterable {
    case circleLarge, circleMedium, circleSmall
    case squareLarge, squareMedium, squareSmall
    case slashLarge, slashMedium, slashSmall
    case backslashLarge, backslashMedium, backslashSmall

    var offsets: [IntPoint] {
        switch self {
        case .circleLarge: Bitmap.penOffsets(width: 7)
        case .circleMedium: Bitmap.penOffsets(width: 4)
        case .circleSmall: [.zero]
        case .squareLarge: Bitmap.squareOffsets(8)
        case .squareMedium: Bitmap.squareOffsets(5)
        case .squareSmall: Bitmap.squareOffsets(2)
        case .slashLarge: Self.diagonal(8, forward: true)
        case .slashMedium: Self.diagonal(5, forward: true)
        case .slashSmall: Self.diagonal(2, forward: true)
        case .backslashLarge: Self.diagonal(8, forward: false)
        case .backslashMedium: Self.diagonal(5, forward: false)
        case .backslashSmall: Self.diagonal(2, forward: false)
        }
    }

    private static func diagonal(_ n: Int, forward: Bool) -> [IntPoint] {
        (0..<n).map { i in IntPoint(i - n / 2, (forward ? n - 1 - i : i) - n / 2) }
    }
}

enum Options {
    static let eraserSizes = [4, 6, 8, 10]
    static let airbrushSizes = [9, 16, 24]
    static let lineWidths = [1, 2, 3, 4, 5]
    static let magnifierLevels = [1, 2, 6, 8]
    static let zoomLevels = [1, 2, 4, 6, 8]
}

enum Palette {
    static let standard: [RGBA] = [
        0x000000, 0x808080, 0x800000, 0x808000, 0x008000, 0x008080, 0x000080,
        0x800080, 0x808040, 0x004040, 0x0080FF, 0x004080, 0x8000FF, 0x804000,
        0xFFFFFF, 0xC0C0C0, 0xFF0000, 0xFFFF00, 0x00FF00, 0x00FFFF, 0x0000FF,
        0xFF00FF, 0xFFFF80, 0x00FF80, 0x80FFFF, 0x8080FF, 0xFF0080, 0xFF8040,
    ].map(RGBA.init(hex:))

    /// Two rows of 14, stored row by row.
    static let columns = 14
}

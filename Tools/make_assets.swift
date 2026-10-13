// Renders website/README assets with the app's own engine.
// Build: swiftc -o /tmp/make_assets Sources/Engine/Bitmap.swift Sources/Engine/TextLayout.swift \
//          Sources/Engine/Tools.swift Sources/UI/ToolIcons.swift <copy of Tools/make_assets.swift named main.swift>
// Run:   /tmp/make_assets <output-dir>
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

let out = CommandLine.arguments[1]
func write(_ b: Bitmap, _ name: String) {
    try! b.encoded(as: .png)!.write(to: URL(fileURLWithPath: "\(out)/\(name)"))
}

// Tool icons, named for the web toolbox.
let iconNames: [Tool: String] = [
    .freeSelect: "free-select", .rectSelect: "select", .eraser: "eraser", .fill: "fill", .picker: "picker",
    .magnifier: "magnifier", .pencil: "pencil", .brush: "brush", .airbrush: "airbrush", .text: "text",
    .line: "line", .curve: "curve", .rectangle: "rectangle", .polygon: "polygon", .ellipse: "ellipse",
    .roundedRectangle: "rounded-rectangle",
]
MainActor.assumeIsolated {
for (tool, name) in iconNames {
    let data = NSMutableData()
    let dest = CGImageDestinationCreateWithData(data as CFMutableData, UTType.png.identifier as CFString, 1, nil)!
    CGImageDestinationAddImage(dest, ToolIcons.image(for: tool)!, nil)
    CGImageDestinationFinalize(dest)
    try! (data as Data).write(to: URL(fileURLWithPath: "\(out)/tools/\(name).png"))
}
}

// A demo picture drawn only with the classic palette and Paint-style primitives.
func c(_ hex: UInt32) -> Pixel { RGBA(hex: hex).pixel }
var img = Bitmap(width: 640, height: 480, fill: c(0x80FFFF))
let black = c(0x000000)
// Sun with rays.
for i in 0..<12 {
    let a = Double(i) * .pi / 6
    img.drawLine(IntPoint(560 + Int(cos(a) * 52), 80 + Int(sin(a) * 52)), IntPoint(560 + Int(cos(a) * 72), 80 + Int(sin(a) * 72)),
                 offsets: Bitmap.penOffsets(width: 3), color: c(0xFF8040))
}
img.drawShape(.ellipse, in: IntRect(x: 516, y: 36, width: 88, height: 88), lineWidth: 3, stroke: c(0xFF8040), fill: c(0xFFFF00))
// Rainbow.
for (i, hex) in [0xFF0000, 0xFF8040, 0xFFFF00, 0x00FF00, 0x0080FF, 0x8000FF].enumerated() {
    let r = 150 - i * 9
    img.drawShape(.ellipse, in: IntRect(x: 300 - r, y: 330 - r, width: r * 2, height: r * 2), lineWidth: 9, stroke: c(UInt32(hex)), fill: nil)
}
img.drawShape(.ellipse, in: IntRect(x: 300 - 96, y: 330 - 96, width: 192, height: 192), lineWidth: 1, stroke: nil, fill: c(0x80FFFF))
// Clouds.
for (x, y) in [(70, 70), (110, 55), (150, 72), (380, 40), (420, 30), (455, 45)] {
    img.drawShape(.ellipse, in: IntRect(x: x, y: y, width: 70, height: 40), lineWidth: 1, stroke: nil, fill: c(0xFFFFFF))
}
// Hills and grass.
img.drawShape(.ellipse, in: IntRect(x: -120, y: 300, width: 520, height: 260), lineWidth: 2, stroke: black, fill: c(0x00FF80))
img.drawShape(.ellipse, in: IntRect(x: 280, y: 320, width: 520, height: 260), lineWidth: 2, stroke: black, fill: c(0x008000))
// House.
img.drawShape(.rectangle, in: IntRect(x: 90, y: 300, width: 150, height: 110), lineWidth: 2, stroke: black, fill: c(0xFF0000))
img.drawPolygon([IntPoint(78, 302), IntPoint(165, 235), IntPoint(252, 302)], lineWidth: 2, stroke: black, fill: c(0x800000))
img.drawShape(.rectangle, in: IntRect(x: 150, y: 350, width: 32, height: 60), lineWidth: 2, stroke: black, fill: c(0x804000))
for x in [105, 200] {
    img.drawShape(.rectangle, in: IntRect(x: x, y: 320, width: 26, height: 24), lineWidth: 2, stroke: black, fill: c(0x80FFFF))
    img.drawLine(IntPoint(x + 13, 320), IntPoint(x + 13, 343), offsets: [.zero], color: black)
    img.drawLine(IntPoint(x, 332), IntPoint(x + 25, 332), offsets: [.zero], color: black)
}
// Tree.
img.drawShape(.rectangle, in: IntRect(x: 488, y: 330, width: 22, height: 70), lineWidth: 2, stroke: black, fill: c(0x804000))
img.drawShape(.ellipse, in: IntRect(x: 450, y: 250, width: 100, height: 100), lineWidth: 2, stroke: black, fill: c(0x00FF00))
for (x, y) in [(475, 280), (510, 300), (490, 320), (525, 270)] {
    img.drawShape(.ellipse, in: IntRect(x: x, y: y, width: 9, height: 9), lineWidth: 1, stroke: black, fill: c(0xFF0000))
}
// Pixel text.
let style = TextLayout.Style(fontName: "Comic Sans MS", size: 30, bold: true)
img.drawText(TextLayout(text: "Hello from RetroPaint!", style: style, color: RGBA(hex: 0x000080),
                        size: CGSize(width: 420, height: 50)), at: IntPoint(24, 140))
write(img, "demo.png")

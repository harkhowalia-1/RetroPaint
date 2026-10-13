import SwiftUI

enum XP {
    static let face = Color(red: 0xEC / 255, green: 0xE9 / 255, blue: 0xD8 / 255)
    static let highlight = Color.white
    static let shadow = Color(red: 0xAC / 255, green: 0xA8 / 255, blue: 0x99 / 255)
    static let darkShadow = Color(red: 0x71 / 255, green: 0x6F / 255, blue: 0x64 / 255)
    static let selection = Color(red: 0x31 / 255, green: 0x6A / 255, blue: 0xC5 / 255)
    static let navy = Color(red: 0, green: 0, blue: 0.5)

    static var font: Font {
        #if os(macOS)
        .custom("Tahoma", size: 11)
        #else
        .system(size: 13)
        #endif
    }
}

extension RGBA {
    var color: Color { Color(cgColor: cgColor) }
}

/// Classic two-pixel 3D border.
struct Bevel: View {
    enum Style { case raised, sunken, thinSunken }
    var style: Style

    var body: some View {
        Canvas { ctx, size in
            let w = size.width, h = size.height
            func edge(_ inset: CGFloat, _ topLeft: Color, _ bottomRight: Color) {
                var tl = Path()
                tl.addRect(CGRect(x: inset, y: inset, width: w - inset * 2, height: 1))
                tl.addRect(CGRect(x: inset, y: inset, width: 1, height: h - inset * 2))
                ctx.fill(tl, with: .color(topLeft))
                var br = Path()
                br.addRect(CGRect(x: inset, y: h - inset - 1, width: w - inset * 2, height: 1))
                br.addRect(CGRect(x: w - inset - 1, y: inset, width: 1, height: h - inset * 2))
                ctx.fill(br, with: .color(bottomRight))
            }
            switch style {
            case .raised:
                edge(0, XP.highlight, XP.darkShadow)
                edge(1, XP.face, XP.shadow)
            case .sunken:
                edge(0, XP.shadow, XP.highlight)
                edge(1, XP.darkShadow, XP.face)
            case .thinSunken:
                edge(0, XP.shadow, XP.highlight)
            }
        }
        .allowsHitTesting(false)
    }
}

/// The 50% dither used behind a pressed toolbox button.
struct Dither: View {
    var body: some View {
        Canvas { ctx, size in
            ctx.fill(Path(CGRect(origin: .zero, size: size)), with: .color(XP.face))
            var p = Path()
            for y in stride(from: 0, to: Int(size.height), by: 1) {
                for x in stride(from: y % 2, to: Int(size.width), by: 2) { p.addRect(CGRect(x: x, y: y, width: 1, height: 1)) }
            }
            ctx.fill(p, with: .color(.white))
        }
    }
}

struct PixelIcon: View {
    let image: CGImage?
    var body: some View {
        if let image {
            Image(decorative: image, scale: 1).interpolation(.none).resizable().frame(width: 16, height: 16)
        }
    }
}

extension View {
    /// Adds a keyboard shortcut only where menus should own one.
    @ViewBuilder func shortcut(_ key: KeyEquivalent, _ mods: EventModifiers = .command, if enabled: Bool) -> some View {
        if enabled { keyboardShortcut(key, modifiers: mods) } else { self }
    }

    /// Right click on macOS, long press on iOS.
    func onSecondaryAction(_ action: @escaping () -> Void) -> some View {
        #if os(macOS)
        overlay(RightClickCatcher(action: action))
        #else
        onLongPressGesture(minimumDuration: 0.35, perform: action)
        #endif
    }
}

#if os(macOS)
import AppKit

private struct RightClickCatcher: NSViewRepresentable {
    let action: () -> Void

    final class CatcherView: NSView {
        var action: (() -> Void)?
        override func hitTest(_ point: NSPoint) -> NSView? {
            let type = NSApp.currentEvent?.type
            return type == .rightMouseDown || type == .rightMouseUp ? super.hitTest(point) : nil
        }
        override func rightMouseDown(with event: NSEvent) { action?() }
    }

    func makeNSView(context: Context) -> CatcherView { CatcherView() }
    func updateNSView(_ v: CatcherView, context: Context) { v.action = action }
}
#endif

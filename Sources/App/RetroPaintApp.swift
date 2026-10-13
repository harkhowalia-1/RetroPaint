import SwiftUI

@main
struct RetroPaintApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        #if os(macOS)
        .defaultSize(width: 820, height: 640)
        #endif
        .commands { PaintCommands() }
    }
}

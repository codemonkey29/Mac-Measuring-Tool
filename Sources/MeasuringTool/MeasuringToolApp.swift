import SwiftUI

@main
struct MeasuringToolApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var workspace = Workspace()

    var body: some Scene {
        Window("Measuring Tool", id: "main") {
            ContentView()
                .environmentObject(workspace)
        }
        .defaultSize(width: 1100, height: 720)
        .commands {
            WorkspaceCommands(workspace: workspace)
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Needed when run as a bare executable (`swift run` or from Xcode) rather than as a .app,
        // otherwise the window doesn't come to the front or take keyboard input.
        NSApp.setActivationPolicy(.regular)
        NSApp.activate()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }
}

struct WorkspaceCommands: Commands {
    let workspace: Workspace

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("Import Image…") { workspace.importImage() }
                .keyboardShortcut("o")
        }
        CommandGroup(after: .toolbar) {
            Button("Zoom In") { workspace.canvas?.zoomIn() }
                .keyboardShortcut("=")
            Button("Zoom Out") { workspace.canvas?.zoomOut() }
                .keyboardShortcut("-")
            Button("Zoom to Fit") { workspace.canvas?.zoomToFit() }
                .keyboardShortcut("0")
        }
    }
}

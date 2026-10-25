import AppKit
import SwiftUI
import XCTest
@testable import MeasuringTool

/// Renders the main window to PNG files so the layout can be checked without running the app.
/// Only runs when SNAPSHOT_DIR is set, e.g. `SNAPSHOT_DIR=$PWD/snapshots swift test`.
final class SnapshotTests: XCTestCase {
    @MainActor
    func testRenderWindow() throws {
        guard let path = ProcessInfo.processInfo.environment["SNAPSHOT_DIR"] else {
            throw XCTSkip("Set SNAPSHOT_DIR to render snapshots")
        }
        let directory = URL(fileURLWithPath: path)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        _ = NSApplication.shared

        let workspace = Workspace()
        let hostingView = NSHostingView(rootView: ContentView().environmentObject(workspace))
        let window = NSWindow(
            contentRect: CGRect(x: 0, y: 0, width: 1100, height: 720),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        window.appearance = NSAppearance(named: .aqua)
        window.contentView = hostingView
        window.orderFrontRegardless()

        settle()
        try render(hostingView, to: directory.appendingPathComponent("1-empty.png"))

        workspace.setImage(TestImages.ruler(), name: "ruler.png")
        settle()
        try render(hostingView, to: directory.appendingPathComponent("2-imported.png"))

        workspace.setReference(Segment(start: CGPoint(x: 100, y: 100), end: CGPoint(x: 1100, y: 100)), length: 100, unit: .millimeters)
        workspace.tool = .measure
        workspace.addMeasurement(Segment(start: CGPoint(x: 300, y: 400), end: CGPoint(x: 900, y: 800)))
        workspace.addMeasurement(Segment(start: CGPoint(x: 1300, y: 300), end: CGPoint(x: 1300, y: 900)))
        workspace.addMeasurement(Segment(start: CGPoint(x: 300, y: 850), end: CGPoint(x: 900, y: 850)))
        settle()
        try render(hostingView, to: directory.appendingPathComponent("3-measured.png"))

        window.appearance = NSAppearance(named: .darkAqua)
        workspace.canvas?.zoom(by: 2, around: CGPoint(x: 400, y: 300))
        settle()
        try render(hostingView, to: directory.appendingPathComponent("4-measured-dark-zoomed.png"))
        window.close()

        let sheetWorkspace = Workspace()
        sheetWorkspace.pendingReference = Segment(start: .zero, end: CGPoint(x: 1000, y: 0))
        let sheetView = NSHostingView(rootView: ScaleSheet(workspace: sheetWorkspace))
        let sheetWindow = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 360, height: 160), styleMask: [.titled], backing: .buffered, defer: false)
        sheetWindow.isReleasedWhenClosed = false
        sheetWindow.appearance = NSAppearance(named: .aqua)
        sheetWindow.contentView = sheetView
        sheetWindow.setContentSize(sheetView.fittingSize)
        sheetWindow.orderFrontRegardless()
        settle()
        try render(sheetView, to: directory.appendingPathComponent("5-scale-sheet.png"))
        sheetWindow.close()
    }

    @MainActor
    private func settle() {
        RunLoop.main.run(until: Date().addingTimeInterval(0.5))
    }

    @MainActor
    private func render(_ view: NSView, to url: URL) throws {
        view.layoutSubtreeIfNeeded()
        let rep = try XCTUnwrap(view.bitmapImageRepForCachingDisplay(in: view.bounds))
        view.cacheDisplay(in: view.bounds, to: rep)
        try XCTUnwrap(rep.representation(using: .png, properties: [:])).write(to: url)
    }
}

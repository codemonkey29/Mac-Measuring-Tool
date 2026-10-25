import XCTest
@testable import MeasuringTool

final class LengthUnitTests: XCTestCase {
    private let posix = Locale(identifier: "en_US_POSIX")

    func testFormatsToAboutFourSignificantFigures() {
        XCTAssertEqual(LengthUnit.millimeters.format(millimeters: 72.111, locale: posix), "72.11 mm")
        XCTAssertEqual(LengthUnit.centimeters.format(millimeters: 1234, locale: posix), "123.4 cm")
        XCTAssertEqual(LengthUnit.meters.format(millimeters: 1234, locale: posix), "1.234 m")
        XCTAssertEqual(LengthUnit.inches.format(millimeters: 25.4, locale: posix), "1.000 in")
        XCTAssertEqual(LengthUnit.feet.format(millimeters: 152.4, locale: posix), "0.5000 ft")
        XCTAssertEqual(LengthUnit.millimeters.format(millimeters: 12345, locale: posix), "12345 mm")
    }

    func testParsesTypedLengths() {
        XCTAssertEqual(LengthUnit.parse("100"), 100)
        XCTAssertEqual(LengthUnit.parse(" 12.5 "), 12.5)
        XCTAssertEqual(LengthUnit.parse("12,5"), 12.5)
        XCTAssertNil(LengthUnit.parse(""))
        XCTAssertNil(LengthUnit.parse("abc"))
        XCTAssertNil(LengthUnit.parse("0"))
        XCTAssertNil(LengthUnit.parse("-3"))
    }
}

final class WorkspaceTests: XCTestCase {
    @MainActor
    func testScaleAndMeasure() {
        let workspace = Workspace()
        workspace.locale = Locale(identifier: "en_US_POSIX")
        workspace.setImage(TestImages.make(width: 400, height: 300), name: "test.png")
        XCTAssertEqual(workspace.tool, .scale)
        XCTAssertFalse(workspace.isScaled)

        workspace.addMeasurement(Segment(start: .zero, end: CGPoint(x: 30, y: 40)))
        XCTAssertEqual(workspace.latestMeasurementText, "50.0 px")

        workspace.pendingReference = Segment(start: .zero, end: CGPoint(x: 100, y: 0))
        workspace.confirmPendingReference(length: 10, unit: .millimeters)
        XCTAssertNil(workspace.pendingReference)
        XCTAssertEqual(workspace.tool, .measure)
        XCTAssertEqual(workspace.millimetersPerPixel ?? 0, 0.1, accuracy: 1e-12)
        XCTAssertEqual(workspace.latestMeasurementText, "5.000 mm")

        workspace.displayUnit = .centimeters
        XCTAssertEqual(workspace.latestMeasurementText, "0.5000 cm")

        workspace.removeLastMeasurement()
        XCTAssertNil(workspace.latestMeasurementText)
    }

    @MainActor
    func testImportingResetsScaleAndMeasurements() {
        let workspace = Workspace()
        workspace.setImage(TestImages.make(width: 10, height: 10), name: "a")
        workspace.setReference(Segment(start: .zero, end: CGPoint(x: 5, y: 0)), length: 1, unit: .inches)
        workspace.addMeasurement(Segment(start: .zero, end: CGPoint(x: 1, y: 1)))
        workspace.setImage(TestImages.make(width: 10, height: 10), name: "b")
        XCTAssertFalse(workspace.isScaled)
        XCTAssertTrue(workspace.measurements.isEmpty)
    }
}

final class ImageLoaderTests: XCTestCase {
    private var directory: URL!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try FileManager.default.removeItem(at: directory)
    }

    func testAppliesExifOrientation() throws {
        // A 200×100 JPEG tagged "rotate 90°", like a portrait photo from a phone.
        let url = directory.appendingPathComponent("rotated.jpg")
        try TestImages.write(TestImages.make(width: 200, height: 100), to: url, type: .jpeg, orientation: 6)
        let image = try ImageLoader.load(url)
        XCTAssertEqual(image.width, 100)
        XCTAssertEqual(image.height, 200)
    }

    func testLoadsPNGAtFullSize() throws {
        let url = directory.appendingPathComponent("image.png")
        try TestImages.write(TestImages.make(width: 321, height: 123), to: url, type: .png)
        let image = try ImageLoader.load(url)
        XCTAssertEqual(image.width, 321)
        XCTAssertEqual(image.height, 123)
    }

    func testLoadsHEIC() throws {
        let url = directory.appendingPathComponent("image.heic")
        do {
            try TestImages.write(TestImages.make(width: 256, height: 128), to: url, type: .heic)
        } catch {
            throw XCTSkip("This Mac can't encode HEIC")
        }
        let image = try ImageLoader.load(url)
        XCTAssertEqual(image.width, 256)
        XCTAssertEqual(image.height, 128)
    }

    func testRejectsNonImages() throws {
        let url = directory.appendingPathComponent("notes.txt")
        try "not an image".write(to: url, atomically: true, encoding: .utf8)
        XCTAssertThrowsError(try ImageLoader.load(url))
    }
}

final class CanvasTests: XCTestCase {
    @MainActor
    private func makeCanvas() -> CanvasView {
        let workspace = Workspace()
        let canvas = CanvasView(workspace: workspace)
        canvas.frame = CGRect(x: 0, y: 0, width: 848, height: 648)
        workspace.setImage(TestImages.make(width: 1600, height: 1200), name: "test.png")
        canvas.workspaceDidChange()
        return canvas
    }

    @MainActor
    func testFitsAndCentresTheImage() {
        let canvas = makeCanvas()
        XCTAssertEqual(canvas.zoomScale, 0.5, accuracy: 1e-9) // (848 - 2 × 24) / 1600
        let centre = canvas.viewPoint(CGPoint(x: 800, y: 600))
        XCTAssertEqual(centre.x, 424, accuracy: 1e-9)
        XCTAssertEqual(centre.y, 324, accuracy: 1e-9)
    }

    @MainActor
    func testZoomKeepsThePointUnderThePointer() {
        let canvas = makeCanvas()
        let pointer = CGPoint(x: 250, y: 180)
        let before = canvas.imagePoint(pointer)
        canvas.zoom(by: 3, around: pointer)
        let after = canvas.imagePoint(pointer)
        XCTAssertEqual(canvas.zoomScale, 1.5, accuracy: 1e-9)
        XCTAssertEqual(before.x, after.x, accuracy: 1e-9)
        XCTAssertEqual(before.y, after.y, accuracy: 1e-9)

        canvas.zoomToFit()
        XCTAssertEqual(canvas.zoomScale, 0.5, accuracy: 1e-9)
    }
}

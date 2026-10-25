import AppKit
import UniformTypeIdentifiers

enum Tool {
    case scale, measure, pan
}

/// A straight line between two points, in image pixel coordinates (origin top-left).
struct Segment: Equatable {
    var start: CGPoint
    var end: CGPoint

    /// Length in image pixels.
    var length: Double { Double(hypot(end.x - start.x, end.y - start.y)) }
}

/// The image, its scale and its measurements. View-only state such as zoom and pan lives in
/// `CanvasView`.
@MainActor
final class Workspace: ObservableObject {
    @Published private(set) var image: CGImage?
    @Published private(set) var imageName = ""
    @Published var tool = Tool.pan

    @Published private(set) var reference: Segment?
    @Published private(set) var referenceLength = 0.0
    @Published private(set) var referenceUnit = LengthUnit.millimeters
    /// A scale line that has been drawn but not yet given its real length.
    @Published var pendingReference: Segment?

    @Published private(set) var measurements: [Segment] = []
    @Published var displayUnit = LengthUnit.millimeters

    @Published var errorMessage: String?
    @Published var zoomPercent = 100

    weak var canvas: CanvasView?
    var locale = Locale.current

    // MARK: Image

    func importImage() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        panel.message = "Choose an image to measure"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        open(url)
    }

    func open(_ url: URL) {
        do {
            setImage(try ImageLoader.load(url), name: url.lastPathComponent)
        } catch {
            errorMessage = "“\(url.lastPathComponent)” couldn’t be opened as an image."
        }
    }

    /// Imports an image, or an image file, from the pasteboard. Returns false if there isn't one.
    @discardableResult
    func paste(from pasteboard: NSPasteboard = .general) -> Bool {
        if pasteboard.canReadObject(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) {
            // A file copied in Finder. Its icon is on the pasteboard too, so don't fall through to that.
            guard let url = Self.imageFileURL(on: pasteboard) else { return false }
            open(url)
            return true
        }
        for type in pasteboard.types ?? [] where UTType(type.rawValue)?.conforms(to: .image) == true {
            if let data = pasteboard.data(forType: type), let image = try? ImageLoader.load(data) {
                setImage(image, name: "Pasted Image")
                return true
            }
        }
        return false
    }

    static func imageFileURL(on pasteboard: NSPasteboard) -> URL? {
        let options: [NSPasteboard.ReadingOptionKey: Any] = [
            .urlReadingFileURLsOnly: true,
            .urlReadingContentsConformToTypes: [UTType.image.identifier],
        ]
        return (pasteboard.readObjects(forClasses: [NSURL.self], options: options) as? [URL])?.first
    }

    func setImage(_ image: CGImage, name: String) {
        self.image = image
        imageName = name
        reference = nil
        referenceLength = 0
        pendingReference = nil
        measurements = []
        tool = .scale
    }

    func selectTool(_ tool: Tool) {
        if image != nil { self.tool = tool }
    }

    // MARK: Scale

    /// Real-world millimetres per image pixel, once a scale has been set.
    var millimetersPerPixel: Double? {
        guard let reference, reference.length > 0, referenceLength > 0 else { return nil }
        return referenceLength * referenceUnit.millimeters / reference.length
    }

    var isScaled: Bool { millimetersPerPixel != nil }

    func setReference(_ segment: Segment, length: Double, unit: LengthUnit) {
        reference = segment
        referenceLength = length
        referenceUnit = unit
        displayUnit = unit
    }

    func confirmPendingReference(length: Double, unit: LengthUnit) {
        guard let segment = pendingReference else { return }
        pendingReference = nil
        setReference(segment, length: length, unit: unit)
        tool = .measure
    }

    var isAskingForScale: Bool {
        get { pendingReference != nil }
        set { if !newValue { pendingReference = nil } }
    }

    var referenceText: String {
        "\(referenceLength.formatted(.number.grouping(.never).locale(locale))) \(referenceUnit.symbol)"
    }

    var scaleDescription: String {
        guard let millimetersPerPixel else { return "Not scaled – lengths are in pixels" }
        return "Scale \(referenceText) · 1 px = \(displayUnit.format(millimeters: millimetersPerPixel, locale: locale))"
    }

    // MARK: Measurements

    func addMeasurement(_ segment: Segment) {
        measurements.append(segment)
    }

    func removeLastMeasurement() {
        if !measurements.isEmpty { measurements.removeLast() }
    }

    func clearMeasurements() {
        measurements.removeAll()
    }

    func pixelText(_ pixels: Double) -> String {
        "\(pixels.formatted(.number.precision(.fractionLength(1)).grouping(.never).locale(locale))) px"
    }

    /// A length in image pixels, in the display unit if a scale is set, otherwise in pixels.
    func lengthText(pixels: Double) -> String {
        guard let millimetersPerPixel else { return pixelText(pixels) }
        return displayUnit.format(millimeters: pixels * millimetersPerPixel, locale: locale)
    }

    var latestMeasurementText: String? {
        measurements.last.map { lengthText(pixels: $0.length) }
    }

    @discardableResult
    func copyLatestMeasurement() -> Bool {
        guard let text = latestMeasurementText else { return false }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        return true
    }

    // MARK: Errors

    var isShowingError: Bool {
        get { errorMessage != nil }
        set { if !newValue { errorMessage = nil } }
    }

    var hint: String {
        guard image != nil else { return "Import an image to begin." }
        switch tool {
        case .scale:
            return "Click two points a known distance apart, then enter that distance. Hold Space to pan."
        case .measure where !isScaled:
            return "Not scaled yet, so lengths are in pixels. Use Scale first."
        case .measure:
            return "Click two points (or drag). Shift snaps to 45°. Delete removes the last line. Hold Space to pan."
        case .pan:
            return "Drag to pan. Scroll or pinch to zoom. Double-click to zoom in, ⌥ double-click to zoom out."
        }
    }
}

import AppKit
import SwiftUI

struct CanvasRepresentable: NSViewRepresentable {
    @ObservedObject var workspace: Workspace

    func makeNSView(context: Context) -> CanvasView {
        let canvas = CanvasView(workspace: workspace)
        workspace.canvas = canvas
        return canvas
    }

    func updateNSView(_ canvas: CanvasView, context: Context) {
        canvas.workspaceDidChange()
    }
}

/// The workspace: shows the image, handles zooming, panning and picking points, and draws the
/// scale line and measurements on top.
final class CanvasView: NSView {
    let workspace: Workspace

    /// View points per image pixel.
    private(set) var zoomScale: CGFloat = 1
    /// Where the image's top-left corner is, in view coordinates.
    private(set) var imageOrigin = CGPoint.zero
    /// While true, the image is re-fitted whenever the view is resized.
    private var fitsWindow = true

    private let imageView = ImageLayerView(frame: .zero)
    private let overlay = OverlayView()
    private var displayedImage: CGImage?
    private var displayedTool: Tool?

    // Picking points for the scale or a measurement. Points are in image coordinates.
    private var anchor: CGPoint?
    private var hover: CGPoint?
    private var pressLocation: CGPoint?
    private var draggedFromAnchor = false
    private var shiftDown = false
    private var lastMouseLocation: CGPoint?

    private var spaceDown = false
    private var panStart: (mouse: CGPoint, origin: CGPoint)?
    private var isDropTargeted = false
    private var zoomPublishPending = false

    private static let zoomRange: ClosedRange<CGFloat> = 0.01...64
    private static let zoomStep: CGFloat = 1.5
    private static let measureColor = NSColor.systemCyan
    private static let scaleColor = NSColor.systemOrange

    init(workspace: Workspace) {
        self.workspace = workspace
        super.init(frame: .zero)
        wantsLayer = true
        clipsToBounds = true
        imageView.isHidden = true
        addSubview(imageView)
        overlay.canvas = self
        overlay.autoresizingMask = [.width, .height]
        addSubview(overlay)
        addTrackingArea(NSTrackingArea(
            rect: .zero,
            options: [.mouseMoved, .cursorUpdate, .activeInKeyWindow, .inVisibleRect],
            owner: self,
            userInfo: nil
        ))
        registerForDraggedTypes([.fileURL])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.underPageBackgroundColor.setFill()
        dirtyRect.fill()
    }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        overlay.frame = bounds
        if fitsWindow { zoomToFit() } else { layoutImage() }
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.window?.makeFirstResponder(self)
        }
    }

    override func resignFirstResponder() -> Bool {
        spaceDown = false
        return super.resignFirstResponder()
    }

    func workspaceDidChange() {
        if workspace.image !== displayedImage {
            displayedImage = workspace.image
            imageView.image = displayedImage
            cancelPicking()
            // Fit now, or on the first resize if the view hasn't been laid out yet.
            fitsWindow = true
            zoomToFit()
            layoutImage()
            window?.makeFirstResponder(self)
        }
        if workspace.tool != displayedTool {
            displayedTool = workspace.tool
            cancelPicking()
        }
        updateCursor()
        overlay.needsDisplay = true
    }

    // MARK: Coordinates

    func viewPoint(_ point: CGPoint) -> CGPoint {
        CGPoint(x: imageOrigin.x + point.x * zoomScale, y: imageOrigin.y + point.y * zoomScale)
    }

    func imagePoint(_ point: CGPoint) -> CGPoint {
        CGPoint(x: (point.x - imageOrigin.x) / zoomScale, y: (point.y - imageOrigin.y) / zoomScale)
    }

    private func clampedImagePoint(_ location: CGPoint) -> CGPoint {
        let point = imagePoint(location)
        guard let image = displayedImage else { return point }
        return CGPoint(x: min(max(point.x, 0), CGFloat(image.width)), y: min(max(point.y, 0), CGFloat(image.height)))
    }

    // MARK: Zoom and pan

    func zoomIn() { zoom(by: Self.zoomStep, around: CGPoint(x: bounds.midX, y: bounds.midY)) }
    func zoomOut() { zoom(by: 1 / Self.zoomStep, around: CGPoint(x: bounds.midX, y: bounds.midY)) }

    /// Zooms while keeping the image point under `location` where it is.
    func zoom(by factor: CGFloat, around location: CGPoint) {
        guard displayedImage != nil else { return }
        let fixedPoint = imagePoint(location)
        zoomScale = min(max(zoomScale * factor, Self.zoomRange.lowerBound), Self.zoomRange.upperBound)
        imageOrigin = CGPoint(x: location.x - fixedPoint.x * zoomScale, y: location.y - fixedPoint.y * zoomScale)
        fitsWindow = false
        transformDidChange()
    }

    func zoomToFit() {
        guard let image = displayedImage, bounds.width > 0, bounds.height > 0 else { return }
        let margin: CGFloat = 24
        let width = CGFloat(image.width), height = CGFloat(image.height)
        zoomScale = min(max(bounds.width - 2 * margin, 1) / width, max(bounds.height - 2 * margin, 1) / height)
        imageOrigin = CGPoint(x: (bounds.width - width * zoomScale) / 2, y: (bounds.height - height * zoomScale) / 2)
        fitsWindow = true
        transformDidChange()
    }

    private func pan(by delta: CGPoint) {
        imageOrigin.x += delta.x
        imageOrigin.y += delta.y
        fitsWindow = false
        transformDidChange()
    }

    private func transformDidChange() {
        layoutImage()
        // Keep the line being drawn attached to the pointer while zooming or panning mid-measurement.
        if anchor != nil, let lastMouseLocation {
            hover = clampedImagePoint(lastMouseLocation)
        }
        overlay.needsDisplay = true
        publishZoom()
    }

    private func layoutImage() {
        guard let image = displayedImage else {
            imageView.isHidden = true
            return
        }
        imageView.isHidden = false
        imageView.frame = CGRect(
            x: imageOrigin.x, y: imageOrigin.y,
            width: CGFloat(image.width) * zoomScale, height: CGFloat(image.height) * zoomScale
        )
        // Show hard-edged pixels when zoomed right in, so points can be placed precisely.
        imageView.showsPixels = zoomScale >= 4
    }

    private func publishZoom() {
        guard !zoomPublishPending else { return }
        zoomPublishPending = true
        // Deferred, because this can run during a SwiftUI update, where publishing isn't allowed.
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.zoomPublishPending = false
            let percent = Int((self.zoomScale * 100).rounded())
            if self.workspace.zoomPercent != percent { self.workspace.zoomPercent = percent }
        }
    }

    private func beginPan(at location: CGPoint) {
        guard displayedImage != nil else { return }
        panStart = (location, imageOrigin)
        NSCursor.closedHand.set()
    }

    private func endPan() {
        panStart = nil
        updateCursor()
    }

    // MARK: Mouse

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        let location = convert(event.locationInWindow, from: nil)
        lastMouseLocation = location
        guard displayedImage != nil else {
            if event.clickCount == 2 { workspace.importImage() }
            return
        }

        if spaceDown || workspace.tool == .pan {
            if !spaceDown && event.clickCount == 2 {
                zoom(by: event.modifierFlags.contains(.option) ? 0.5 : 2, around: location)
            } else {
                beginPan(at: location)
            }
            return
        }

        let point = clampedImagePoint(location)
        if let anchor {
            finishSegment(from: anchor, to: snapped(point, from: anchor, shift: event.modifierFlags.contains(.shift)))
        } else {
            anchor = point
            hover = point
            pressLocation = location
            draggedFromAnchor = false
            overlay.needsDisplay = true
        }
    }

    override func mouseDragged(with event: NSEvent) {
        let location = convert(event.locationInWindow, from: nil)
        lastMouseLocation = location
        if let panStart {
            imageOrigin = CGPoint(
                x: panStart.origin.x + location.x - panStart.mouse.x,
                y: panStart.origin.y + location.y - panStart.mouse.y
            )
            fitsWindow = false
            transformDidChange()
            return
        }
        guard anchor != nil else { return }
        shiftDown = event.modifierFlags.contains(.shift)
        hover = clampedImagePoint(location)
        if let pressLocation, hypot(location.x - pressLocation.x, location.y - pressLocation.y) > 4 {
            draggedFromAnchor = true
        }
        overlay.needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        if panStart != nil {
            endPan()
            return
        }
        // Press-drag-release makes a line too; a plain click waits for the second click.
        guard let anchor, draggedFromAnchor else { return }
        let point = clampedImagePoint(convert(event.locationInWindow, from: nil))
        finishSegment(from: anchor, to: snapped(point, from: anchor, shift: event.modifierFlags.contains(.shift)))
    }

    override func mouseMoved(with event: NSEvent) {
        let location = convert(event.locationInWindow, from: nil)
        lastMouseLocation = location
        updateCursor()
        guard anchor != nil else { return }
        shiftDown = event.modifierFlags.contains(.shift)
        hover = clampedImagePoint(location)
        overlay.needsDisplay = true
    }

    // The middle mouse button pans in any tool.
    override func otherMouseDown(with event: NSEvent) {
        beginPan(at: convert(event.locationInWindow, from: nil))
    }

    override func otherMouseDragged(with event: NSEvent) {
        mouseDragged(with: event)
    }

    override func otherMouseUp(with event: NSEvent) {
        endPan()
    }

    override func scrollWheel(with event: NSEvent) {
        guard displayedImage != nil else { return }
        let location = convert(event.locationInWindow, from: nil)
        lastMouseLocation = location
        if event.hasPreciseScrollingDeltas && !event.modifierFlags.contains(.command) {
            // Trackpad or Magic Mouse: two-finger scrolling pans.
            pan(by: CGPoint(x: event.scrollingDeltaX, y: event.scrollingDeltaY))
        } else {
            // Mouse wheel, or ⌘-scroll: zoom around the pointer. Wheel away from you zooms in,
            // whatever the natural scrolling setting.
            let delta = event.isDirectionInvertedFromDevice ? -event.scrollingDeltaY : event.scrollingDeltaY
            zoom(by: pow(event.hasPreciseScrollingDeltas ? 1.01 : 1.2, delta), around: location)
        }
    }

    override func magnify(with event: NSEvent) {
        zoom(by: max(1 + event.magnification, 0.1), around: convert(event.locationInWindow, from: nil))
    }

    override func smartMagnify(with event: NSEvent) {
        if fitsWindow {
            zoom(by: 2, around: convert(event.locationInWindow, from: nil))
        } else {
            zoomToFit()
        }
    }

    // MARK: Keyboard

    override func keyDown(with event: NSEvent) {
        switch event.keyCode {
        case 49: // Space: hold to pan in any tool
            if !spaceDown {
                spaceDown = true
                updateCursor()
            }
        case 53: // Esc
            cancelPicking()
        case 51, 117: // Delete, Forward Delete
            if anchor != nil { cancelPicking() } else { workspace.removeLastMeasurement() }
        default:
            let isPlainKey = event.modifierFlags.intersection([.command, .control, .option]).isEmpty
            switch isPlainKey ? (event.charactersIgnoringModifiers ?? "").lowercased() : "" {
            case "s": workspace.selectTool(.scale)
            case "m": workspace.selectTool(.measure)
            case "p": workspace.selectTool(.pan)
            default: super.keyDown(with: event)
            }
        }
    }

    override func keyUp(with event: NSEvent) {
        if event.keyCode == 49 {
            spaceDown = false
            updateCursor()
        } else {
            super.keyUp(with: event)
        }
    }

    override func flagsChanged(with event: NSEvent) {
        shiftDown = event.modifierFlags.contains(.shift)
        overlay.needsDisplay = true
        super.flagsChanged(with: event)
    }

    // Edit > Copy and Edit > Paste.
    @objc func copy(_ sender: Any?) {
        if !workspace.copyLatestMeasurement() { NSSound.beep() }
    }

    @objc func paste(_ sender: Any?) {
        if !workspace.paste() { NSSound.beep() }
    }

    // MARK: Picking points

    /// With Shift held, snaps the line to the nearest 45°.
    private func snapped(_ point: CGPoint, from start: CGPoint, shift: Bool) -> CGPoint {
        guard shift else { return point }
        let dx = point.x - start.x, dy = point.y - start.y
        let angle = (atan2(dy, dx) / (.pi / 4)).rounded() * (.pi / 4)
        let length = dx * cos(angle) + dy * sin(angle)
        return CGPoint(x: start.x + length * cos(angle), y: start.y + length * sin(angle))
    }

    private func finishSegment(from start: CGPoint, to end: CGPoint) {
        cancelPicking()
        let segment = Segment(start: start, end: end)
        // Ignore accidental double clicks on the same spot.
        guard segment.length * zoomScale >= 2 else { return }
        switch workspace.tool {
        case .scale: workspace.pendingReference = segment
        case .measure: workspace.addMeasurement(segment)
        case .pan: break
        }
    }

    private func cancelPicking() {
        anchor = nil
        hover = nil
        pressLocation = nil
        draggedFromAnchor = false
        overlay.needsDisplay = true
    }

    // MARK: Cursor

    override func cursorUpdate(with event: NSEvent) {
        updateCursor()
    }

    private func updateCursor() {
        guard let window, bounds.contains(convert(window.mouseLocationOutsideOfEventStream, from: nil)) else { return }
        currentCursor.set()
    }

    private var currentCursor: NSCursor {
        guard displayedImage != nil else { return .arrow }
        if panStart != nil { return .closedHand }
        if spaceDown || workspace.tool == .pan { return .openHand }
        return .crosshair
    }

    // MARK: Drag and drop

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        guard Workspace.imageFileURL(on: sender.draggingPasteboard) != nil else { return [] }
        isDropTargeted = true
        overlay.needsDisplay = true
        return .copy
    }

    override func draggingExited(_ sender: NSDraggingInfo?) {
        isDropTargeted = false
        overlay.needsDisplay = true
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        isDropTargeted = false
        overlay.needsDisplay = true
        guard let url = Workspace.imageFileURL(on: sender.draggingPasteboard) else { return false }
        workspace.open(url)
        return true
    }

    // MARK: Drawing

    fileprivate func drawOverlay() {
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        guard displayedImage != nil else {
            drawEmptyState()
            return
        }

        if let reference = workspace.reference {
            drawSegment(reference, color: Self.scaleColor, label: "Scale \(workspace.referenceText)", in: context)
        }
        for measurement in workspace.measurements {
            drawSegment(measurement, color: Self.measureColor, label: workspace.lengthText(pixels: measurement.length), in: context)
        }
        if let pending = workspace.pendingReference {
            drawSegment(pending, color: Self.scaleColor, label: workspace.pixelText(pending.length), dashed: true, in: context)
        }
        if let anchor, let hover {
            let segment = Segment(start: anchor, end: snapped(hover, from: anchor, shift: shiftDown))
            if workspace.tool == .scale {
                drawSegment(segment, color: Self.scaleColor, label: workspace.pixelText(segment.length), dashed: true, in: context)
            } else {
                drawSegment(segment, color: Self.measureColor, label: workspace.lengthText(pixels: segment.length), dashed: true, in: context)
            }
        }

        if isDropTargeted {
            let border = NSBezierPath(rect: bounds.insetBy(dx: 2, dy: 2))
            border.lineWidth = 4
            NSColor.controlAccentColor.setStroke()
            border.stroke()
        }
    }

    private func drawSegment(_ segment: Segment, color: NSColor, label: String?, dashed: Bool = false, in context: CGContext) {
        let a = viewPoint(segment.start), b = viewPoint(segment.end)
        let length = hypot(b.x - a.x, b.y - a.y)
        // Unit vector across the line, used for the end ticks and to place the label.
        var normal = length > 0 ? CGPoint(x: -(b.y - a.y) / length, y: (b.x - a.x) / length) : CGPoint(x: 0, y: -1)
        if normal.y > 0 || (normal.y == 0 && normal.x > 0) {
            normal = CGPoint(x: -normal.x, y: -normal.y) // put labels above (or left of) the line
        }

        let tick: CGFloat = 7
        let path = CGMutablePath()
        path.move(to: a)
        path.addLine(to: b)
        for end in [a, b] {
            path.move(to: CGPoint(x: end.x - normal.x * tick, y: end.y - normal.y * tick))
            path.addLine(to: CGPoint(x: end.x + normal.x * tick, y: end.y + normal.y * tick))
        }

        context.saveGState()
        context.setLineCap(.round)
        // A dark halo keeps lines visible on both light and dark images.
        context.addPath(path)
        context.setStrokeColor(NSColor.black.withAlphaComponent(0.55).cgColor)
        context.setLineWidth(4)
        context.strokePath()
        context.addPath(path)
        context.setStrokeColor(color.cgColor)
        context.setLineWidth(1.5)
        if dashed { context.setLineDash(phase: 0, lengths: [6, 4]) }
        context.strokePath()
        context.restoreGState()

        if let label {
            drawLabel(label, color: color, at: CGPoint(x: (a.x + b.x) / 2, y: (a.y + b.y) / 2), offset: normal)
        }
    }

    private func drawLabel(_ text: String, color: NSColor, at point: CGPoint, offset normal: CGPoint) {
        let string = NSAttributedString(string: text, attributes: [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .semibold),
            .foregroundColor: NSColor.black,
        ])
        let textSize = string.size()
        let padding = CGSize(width: 6, height: 2)
        let size = CGSize(width: textSize.width + padding.width * 2, height: textSize.height + padding.height * 2)
        // Sit the label just off the line, on the side `normal` points to.
        let distance = 8 + abs(normal.x) * size.width / 2 + abs(normal.y) * size.height / 2
        let center = CGPoint(x: point.x + normal.x * distance, y: point.y + normal.y * distance)
        let rect = CGRect(x: center.x - size.width / 2, y: center.y - size.height / 2, width: size.width, height: size.height)

        color.withAlphaComponent(0.92).setFill()
        NSBezierPath(roundedRect: rect, xRadius: 4, yRadius: 4).fill()
        string.draw(at: CGPoint(x: rect.minX + padding.width, y: rect.minY + padding.height))
    }

    private func drawEmptyState() {
        let frame = bounds.insetBy(dx: 40, dy: 40)
        guard frame.width > 200, frame.height > 120 else { return }
        let border = NSBezierPath(roundedRect: frame, xRadius: 14, yRadius: 14)
        border.lineWidth = 2
        border.setLineDash([8, 6], count: 2, phase: 0)
        (isDropTargeted ? NSColor.controlAccentColor : NSColor.tertiaryLabelColor).setStroke()
        border.stroke()

        let lines: [(String, NSFont, NSColor)] = [
            ("Import an image to get started", .systemFont(ofSize: 18, weight: .medium), .secondaryLabelColor),
            ("Click Import, drop an image here, or paste one with ⌘V.", .systemFont(ofSize: 13), .secondaryLabelColor),
            ("JPEG, PNG, HEIC, TIFF, WebP and most camera RAW files work.", .systemFont(ofSize: 12), .tertiaryLabelColor),
        ]
        var y = bounds.midY - 34
        for (text, font, color) in lines {
            let string = NSAttributedString(string: text, attributes: [.font: font, .foregroundColor: color])
            let size = string.size()
            string.draw(at: CGPoint(x: bounds.midX - size.width / 2, y: y))
            y += size.height + 8
        }
    }
}

/// Transparent view above the image where lines and labels are drawn. Mouse events pass
/// through to the canvas.
private final class OverlayView: NSView {
    weak var canvas: CanvasView?

    override var isFlipped: Bool { true }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func draw(_ dirtyRect: NSRect) {
        canvas?.drawOverlay()
    }
}

/// Shows the image as layer contents, so the GPU does the scaling and zooming stays smooth
/// even with very large photos.
private final class ImageLayerView: NSView {
    var image: CGImage? {
        didSet { needsDisplay = true }
    }

    var showsPixels = false {
        didSet { if showsPixels != oldValue { needsDisplay = true } }
    }

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layerContentsRedrawPolicy = .onSetNeedsDisplay
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var wantsUpdateLayer: Bool { true }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func updateLayer() {
        guard let layer else { return }
        layer.contents = image
        layer.contentsGravity = .resize
        layer.magnificationFilter = showsPixels ? .nearest : .linear
        layer.minificationFilter = .trilinear
    }

    // Only used when rendering off screen (e.g. `cacheDisplay`). On screen, `updateLayer` is used.
    override func draw(_ dirtyRect: NSRect) {
        guard let image, let context = NSGraphicsContext.current?.cgContext else { return }
        context.interpolationQuality = showsPixels ? .none : .high
        context.draw(image, in: bounds)
    }
}

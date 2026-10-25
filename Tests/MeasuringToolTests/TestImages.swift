import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

enum TestImages {
    /// Draws an image using top-left-origin coordinates, like the app uses.
    static func make(width: Int, height: Int, draw: (CGContext) -> Void = { _ in }) -> CGImage {
        let context = CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        context.translateBy(x: 0, y: CGFloat(height))
        context.scaleBy(x: 1, y: -1)
        context.setFillColor(CGColor(red: 0.93, green: 0.91, blue: 0.86, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        draw(context)
        return context.makeImage()!
    }

    /// A 1600×1000 "photo" with a ruler where 10 px = 1 mm, and a couple of objects to measure.
    static func ruler() -> CGImage {
        make(width: 1600, height: 1000) { context in
            // Ruler from x = 100 to x = 1100 (100 mm).
            context.setFillColor(CGColor(red: 0.98, green: 0.84, blue: 0.35, alpha: 1))
            context.fill(CGRect(x: 80, y: 100, width: 1040, height: 70))
            context.setStrokeColor(CGColor(gray: 0.1, alpha: 1))
            context.setLineWidth(2)
            for mm in 0...100 {
                let x = CGFloat(100 + mm * 10)
                let tick: CGFloat = mm % 10 == 0 ? 40 : mm % 5 == 0 ? 28 : 16
                context.move(to: CGPoint(x: x, y: 100))
                context.addLine(to: CGPoint(x: x, y: 100 + tick))
            }
            context.strokePath()

            context.setFillColor(CGColor(red: 0.25, green: 0.45, blue: 0.75, alpha: 1))
            context.fill(CGRect(x: 300, y: 400, width: 600, height: 400))
            context.setFillColor(CGColor(red: 0.75, green: 0.3, blue: 0.3, alpha: 1))
            context.fillEllipse(in: CGRect(x: 1150, y: 300, width: 300, height: 600))
        }
    }

    static func write(_ image: CGImage, to url: URL, type: UTType, orientation: Int = 1) throws {
        guard let destination = CGImageDestinationCreateWithURL(url as CFURL, type.identifier as CFString, 1, nil) else {
            throw CocoaError(.fileWriteUnsupportedScheme)
        }
        CGImageDestinationAddImage(destination, image, [kCGImagePropertyOrientation: orientation] as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { throw CocoaError(.fileWriteUnknown) }
    }
}

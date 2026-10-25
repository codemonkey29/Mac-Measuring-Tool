import Foundation
import ImageIO

/// Decodes images with ImageIO, which handles JPEG, PNG, HEIC/HEIF, TIFF, GIF, BMP, WebP and
/// most camera RAW formats.
enum ImageLoader {
    /// Longest side kept in memory; bigger images are downsampled to fit. This doesn't affect
    /// measurements, because the scale is always taken from the same image.
    static let maxPixelSize = 16_384

    struct UnreadableImage: Error {}

    static func load(_ url: URL) throws -> CGImage {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { throw UnreadableImage() }
        return try load(source)
    }

    static func load(_ data: Data) throws -> CGImage {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { throw UnreadableImage() }
        return try load(source)
    }

    private static func load(_ source: CGImageSource) throws -> CGImage {
        let index = CGImageSourceGetPrimaryImageIndex(source)
        let properties = CGImageSourceCopyPropertiesAtIndex(source, index, nil) as? [CFString: Any]
        let width = properties?[kCGImagePropertyPixelWidth] as? Int ?? 0
        let height = properties?[kCGImagePropertyPixelHeight] as? Int ?? 0
        let longestSide = max(width, height)

        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            // Apply the EXIF orientation, so portrait phone photos come in the right way up.
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: longestSide > 0 ? min(longestSide, maxPixelSize) : maxPixelSize,
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, index, options as CFDictionary) else {
            throw UnreadableImage()
        }
        return image
    }
}

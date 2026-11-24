import Foundation
import AppKit
import ImageIO
import UniformTypeIdentifiers

/// Turns any picture into a 3000x3000 JPEG (the size Spotify and most stores ask for).
enum CoverArt {
    static let side = 3000

    enum ArtError: LocalizedError {
        case unreadable
        var errorDescription: String? { "That image couldn't be read." }
    }

    static func image(from url: URL) -> CGImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        return CGImageSourceCreateImageAtIndex(source, 0, nil)
    }

    /// Crops to a centered square, scales to 3000x3000 and saves the cover and a small thumbnail.
    static func save(_ image: CGImage, for song: Song) throws {
        guard let full = square(image, side: side) else { throw ArtError.unreadable }
        try write(full, to: song.artURL, quality: 0.95)
        if let thumb = square(image, side: 400) {
            try write(thumb, to: song.thumbURL, quality: 0.85)
        }
    }

    static func remove(for song: Song) {
        try? FileManager.default.removeItem(at: song.artURL)
        try? FileManager.default.removeItem(at: song.thumbURL)
    }

    private static func square(_ image: CGImage, side: Int) -> CGImage? {
        let w = CGFloat(image.width), h = CGFloat(image.height)
        let edge = min(w, h)
        let crop = CGRect(x: (w - edge) / 2, y: (h - edge) / 2, width: edge, height: edge)
        guard let cropped = image.cropping(to: crop),
              let context = CGContext(data: nil, width: side, height: side,
                                      bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                      bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)
        else { return nil }
        context.interpolationQuality = .high
        context.draw(cropped, in: CGRect(x: 0, y: 0, width: side, height: side))
        return context.makeImage()
    }

    private static func write(_ image: CGImage, to url: URL, quality: Double) throws {
        guard let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.jpeg.identifier as CFString, 1, nil)
        else { throw ArtError.unreadable }
        CGImageDestinationAddImage(destination, image,
                                   [kCGImageDestinationLossyCompressionQuality: quality] as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { throw ArtError.unreadable }
    }
}

/// Small in-memory cache so scrolling the library stays smooth.
enum ThumbnailCache {
    private static let cache = NSCache<NSString, NSImage>()

    static func image(for song: Song) -> NSImage? {
        guard song.hasArt else { return nil }
        let key = "\(song.id.uuidString)-\(song.artRevision)" as NSString
        if let hit = cache.object(forKey: key) { return hit }
        guard let image = NSImage(contentsOf: song.thumbURL) else { return nil }
        cache.setObject(image, forKey: key)
        return image
    }
}

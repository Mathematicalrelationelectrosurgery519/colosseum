import AppKit
import Foundation
import ImageIO

/// Process-wide cache for downsampled grid thumbnails (local files and remote URLs).
enum ImageThumbCache {
    /// Matches import-time thumbs; ~2× a dense grid cell on retina.
    static let defaultMaxPixelSize = 640

    private static let cache: NSCache<NSString, NSImage> = {
        let cache = NSCache<NSString, NSImage>()
        cache.countLimit = 400
        cache.totalCostLimit = 80 * 1024 * 1024
        return cache
    }()

    private static let session: URLSession = {
        let config = URLSessionConfiguration.default
        config.requestCachePolicy = .returnCacheDataElseLoad
        config.urlCache = URLCache(
            memoryCapacity: 32 * 1024 * 1024,
            diskCapacity: 128 * 1024 * 1024,
            diskPath: "ColosseumImageThumbs"
        )
        return URLSession(configuration: config)
    }()

    static func image(for url: URL, maxPixelSize: Int = defaultMaxPixelSize) async -> NSImage? {
        let key = cacheKey(url: url, maxPixelSize: maxPixelSize)
        if let cached = cache.object(forKey: key) {
            return cached
        }

        guard !Task.isCancelled else { return nil }

        let image: NSImage?
        if url.isFileURL {
            image = await Task.detached(priority: .userInitiated) {
                decodeDownsampled(url: url, maxPixelSize: maxPixelSize)
            }.value
        } else {
            image = await decodeRemote(url: url, maxPixelSize: maxPixelSize)
        }

        if let image {
            cache.setObject(image, forKey: key, cost: cost(of: image))
        }
        return image
    }

    static func cachedImage(for url: URL, maxPixelSize: Int = defaultMaxPixelSize) -> NSImage? {
        cache.object(forKey: cacheKey(url: url, maxPixelSize: maxPixelSize))
    }

    // MARK: - Private

    private static func cacheKey(url: URL, maxPixelSize: Int) -> NSString {
        "\(url.absoluteString)#\(maxPixelSize)" as NSString
    }

    private static func cost(of image: NSImage) -> Int {
        let pixels = max(1, Int(image.size.width * image.size.height))
        // Approximate RGBA footprint.
        return pixels * 4
    }

    private static func decodeRemote(url: URL, maxPixelSize: Int) async -> NSImage? {
        do {
            let (data, response) = try await session.data(from: url)
            try Task.checkCancellation()
            if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
                return nil
            }
            return await Task.detached(priority: .userInitiated) {
                decodeDownsampled(data: data, maxPixelSize: maxPixelSize)
            }.value
        } catch {
            return nil
        }
    }

    private static func decodeDownsampled(url: URL, maxPixelSize: Int) -> NSImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        return makeThumbnail(from: source, maxPixelSize: maxPixelSize)
    }

    private static func decodeDownsampled(data: Data, maxPixelSize: Int) -> NSImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        return makeThumbnail(from: source, maxPixelSize: maxPixelSize)
    }

    private static func makeThumbnail(from source: CGImageSource, maxPixelSize: Int) -> NSImage? {
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: max(1, maxPixelSize)
        ]
        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            return nil
        }
        return NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
    }
}

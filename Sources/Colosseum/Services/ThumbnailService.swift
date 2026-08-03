import AppKit
import AVFoundation
import Foundation
import ImageIO

enum ThumbnailService {
    static let maxDimension: CGFloat = 640

    static func generateImageThumbnail(from sourceURL: URL, blockID: UUID) throws -> URL? {
        guard let source = CGImageSourceCreateWithURL(sourceURL as CFURL, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: Int(maxDimension)
        ]
        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            return nil
        }
        let image = NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
        return try writeJPEG(image, blockID: blockID, name: "thumb.jpg")
    }

    static func generateVideoThumbnail(from sourceURL: URL, blockID: UUID) async throws -> URL? {
        let asset = AVURLAsset(url: sourceURL)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: maxDimension, height: maxDimension)
        let time = CMTime(seconds: 0.1, preferredTimescale: 600)
        let (cgImage, _) = try await generator.image(at: time)
        let image = NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
        return try writeJPEG(image, blockID: blockID, name: "thumb.jpg")
    }

    static func imageDimensions(at url: URL) -> (Int, Int) {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
        else { return (0, 0) }
        let w = props[kCGImagePropertyPixelWidth] as? Int ?? 0
        let h = props[kCGImagePropertyPixelHeight] as? Int ?? 0
        return (w, h)
    }

    static func videoMetadata(at url: URL) async -> (width: Int, height: Int, duration: Double) {
        let asset = AVURLAsset(url: url)
        do {
            let duration = try await asset.load(.duration).seconds
            let tracks = try await asset.loadTracks(withMediaType: .video)
            guard let track = tracks.first else { return (0, 0, duration) }
            let size = try await track.load(.naturalSize)
            let transform = try await track.load(.preferredTransform)
            let transformed = size.applying(transform)
            return (Int(abs(transformed.width)), Int(abs(transformed.height)), duration)
        } catch {
            return (0, 0, 0)
        }
    }

    private static func writeJPEG(_ image: NSImage, blockID: UUID, name: String) throws -> URL? {
        guard let tiff = image.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff),
              let data = rep.representation(using: .jpeg, properties: [.compressionFactor: 0.82])
        else { return nil }
        return try MediaLibrary.writeData(data, into: blockID, filename: name)
    }
}

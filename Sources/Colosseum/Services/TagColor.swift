import AppKit
import SwiftUI

enum TagColor {
    /// Deterministic, high-visibility color for a tag on a near-black background.
    static func color(for tag: String) -> Color {
        Color(nsColor(for: tag))
    }

    static func nsColor(for tag: String) -> NSColor {
        let key = TagParser.normalize(tag)
        var hash: UInt64 = 14695981039346656037
        for byte in key.utf8 {
            hash ^= UInt64(byte)
            hash &*= 1099511628211
        }

        // Spread hues; skip a muddy yellow-green band by remapping.
        var hue = Double(hash % 360) / 360.0
        if hue > 0.12 && hue < 0.20 {
            hue += 0.18
        }

        let saturation = 0.58 + Double((hash >> 9) % 20) / 100.0   // 0.58…0.77
        let brightness = 0.78 + Double((hash >> 17) % 14) / 100.0  // 0.78…0.91

        return NSColor(
            hue: CGFloat(hue.truncatingRemainder(dividingBy: 1)),
            saturation: CGFloat(saturation),
            brightness: CGFloat(brightness),
            alpha: 1
        )
    }
}

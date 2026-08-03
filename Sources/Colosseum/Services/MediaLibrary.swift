import Foundation

enum MediaLibrary {
    static var rootURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return base.appendingPathComponent("Colosseum", isDirectory: true)
    }

    static var storeURL: URL {
        rootURL.appendingPathComponent("Colosseum.store")
    }

    static var mediaURL: URL {
        rootURL.appendingPathComponent("Media", isDirectory: true)
    }

    static func ensureDirectories() throws {
        try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: mediaURL, withIntermediateDirectories: true)
    }

    static func blockDirectory(for blockID: UUID) -> URL {
        mediaURL.appendingPathComponent(blockID.uuidString, isDirectory: true)
    }

    static func absoluteURL(relativePath: String) -> URL {
        rootURL.appendingPathComponent(relativePath)
    }

    static func relativePath(from absolute: URL) -> String {
        let root = rootURL.standardizedFileURL.path
        let path = absolute.standardizedFileURL.path
        if path.hasPrefix(root) {
            let trimmed = String(path.dropFirst(root.count))
            return trimmed.hasPrefix("/") ? String(trimmed.dropFirst()) : trimmed
        }
        return absolute.lastPathComponent
    }

    @discardableResult
    static func copyFile(_ source: URL, into blockID: UUID, preferredName: String? = nil) throws -> URL {
        let dir = blockDirectory(for: blockID)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let name = preferredName ?? source.lastPathComponent
        let dest = dir.appendingPathComponent(name)
        if FileManager.default.fileExists(atPath: dest.path) {
            try FileManager.default.removeItem(at: dest)
        }
        try FileManager.default.copyItem(at: source, to: dest)
        return dest
    }

    static func removeBlockFiles(_ blockID: UUID) {
        let dir = blockDirectory(for: blockID)
        try? FileManager.default.removeItem(at: dir)
    }

    static func writeData(_ data: Data, into blockID: UUID, filename: String) throws -> URL {
        let dir = blockDirectory(for: blockID)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let dest = dir.appendingPathComponent(filename)
        try data.write(to: dest, options: .atomic)
        return dest
    }
}

import Foundation
import CryptoKit

actor DiskCache {
    static let shared = DiskCache()

    /// Bumped whenever cache schemas change; old files are ignored.
    static let schemaVersion = "v2"

    private let root: URL

    init() {
        let base = FileManager.default
            .urls(for: .cachesDirectory, in: .userDomainMask)
            .first!
            .appendingPathComponent("com.statusforecast.app", isDirectory: true)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        self.root = base
    }

    private func fileURL(for key: String) -> URL {
        // Prefix every key with the schema version so a schema bump silently
        // invalidates older entries (they live under a different hash).
        let versioned = "\(Self.schemaVersion):\(key)"
        let hash = SHA256.hash(data: Data(versioned.utf8))
            .map { String(format: "%02x", $0) }
            .joined()
        return root.appendingPathComponent(hash + ".cache")
    }

    /// Returns cached data if newer than the supplied TTL, else nil.
    func read(_ key: String, ttl: TimeInterval) -> Data? {
        let url = fileURL(for: key)
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
              let mtime = attrs[.modificationDate] as? Date else { return nil }
        if Date().timeIntervalSince(mtime) > ttl { return nil }
        return try? Data(contentsOf: url)
    }

    /// Returns cached data regardless of staleness (used as fallback).
    func readAny(_ key: String) -> Data? {
        try? Data(contentsOf: fileURL(for: key))
    }

    func write(_ key: String, data: Data) {
        try? data.write(to: fileURL(for: key), options: .atomic)
    }

    /// Sweep cache directory removing entries older than the given TTL.
    /// Run from app bootstrap so disk usage stays bounded.
    func purgeOlderThan(_ seconds: TimeInterval) {
        let fm = FileManager.default
        let cutoff = Date().addingTimeInterval(-seconds)
        guard let files = try? fm.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else { return }
        for f in files {
            guard let vals = try? f.resourceValues(forKeys: [.contentModificationDateKey]),
                  let mtime = vals.contentModificationDate else { continue }
            if mtime < cutoff {
                try? fm.removeItem(at: f)
            }
        }
    }
}

//
//  RecordingStore.swift
//  SurfaceRecorderSDKDemo
//
//  Created by Nazar Kozak on 05.06.2026.
//

import Foundation

/// Persists recordings to Documents/Recordings so the gallery can list them.
enum RecordingStore {
    static var folder: URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let dir = docs.appendingPathComponent("Recordings", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    /// Moves a freshly-written temp recording into the gallery folder.
    @discardableResult
    static func save(_ tempURL: URL) -> URL {
        let dest = folder.appendingPathComponent(tempURL.lastPathComponent)
        try? FileManager.default.removeItem(at: dest)
        do {
            try FileManager.default.moveItem(at: tempURL, to: dest)
            return dest
        } catch {
            return tempURL
        }
    }

    /// All saved recordings, newest first.
    static func all() -> [URL] {
        let keys: [URLResourceKey] = [.creationDateKey]
        let urls = (try? FileManager.default.contentsOfDirectory(
            at: folder, includingPropertiesForKeys: keys)) ?? []
        return urls
            .filter { $0.pathExtension.lowercased() == "mp4" }
            .sorted { lhs, rhs in date(of: lhs) > date(of: rhs) }
    }

    static func delete(_ url: URL) {
        try? FileManager.default.removeItem(at: url)
    }

    private static func date(of url: URL) -> Date {
        (try? url.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? .distantPast
    }
}

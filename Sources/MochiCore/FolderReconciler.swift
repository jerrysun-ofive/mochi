import Foundation

public struct ReconciliationResult: Sendable {
    public let newFiles: [FileMetadata]
    public let changedFiles: [FileMetadata]
    public let removedRelativePaths: [String]
}

public actor FolderReconciler {
    private let extractor = MetadataExtractor()
    private var snapshots: [UUID: [String: FileFingerprint]] = [:]

    public init() {}

    /// Establishes a baseline without returning existing files as new work.
    public func baseline(grantID: UUID, root: URL) throws {
        snapshots[grantID] = try scan(root: root).mapValues(\.fingerprint)
    }

    public func reconcile(grantID: UUID, root: URL) throws -> ReconciliationResult {
        let current = try scan(root: root)
        let previous = snapshots[grantID] ?? [:]
        var newFiles: [FileMetadata] = []
        var changed: [FileMetadata] = []
        for (relativePath, metadata) in current {
            guard let prior = previous[relativePath] else { newFiles.append(metadata); continue }
            if prior != metadata.fingerprint { changed.append(metadata) }
        }
        let removed = previous.keys.filter { current[$0] == nil }.sorted()
        snapshots[grantID] = current.mapValues(\.fingerprint)
        return .init(newFiles: newFiles, changedFiles: changed, removedRelativePaths: removed)
    }

    private func scan(root: URL) throws -> [String: FileMetadata] {
        let urls = try FileManager.default.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey, .isHiddenKey],
            options: [.skipsPackageDescendants]
        )
        var result: [String: FileMetadata] = [:]
        for url in urls {
            guard let metadata = try? extractor.metadata(for: url), metadata.isRegularFile, !metadata.isSymbolicLink else { continue }
            result[url.lastPathComponent] = metadata
        }
        return result
    }
}

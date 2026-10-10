import Foundation

public enum ReadinessResult: Equatable, Sendable { case ready, pending, ignored }

public struct ReadinessProbe: Sendable {
    public static let temporaryExtensions: Set<String> = ["download", "crdownload", "part", "partial", "tmp"]
    private let extractor = MetadataExtractor()

    public init() {}

    public func check(url: URL, delay: Duration = .seconds(2)) async -> ReadinessResult {
        guard !Self.temporaryExtensions.contains(url.pathExtension.lowercased()) else { return .pending }
        guard let first = try? extractor.metadata(for: url), first.isRegularFile, !first.isSymbolicLink else { return .ignored }
        try? await Task.sleep(for: delay)
        guard let second = try? extractor.metadata(for: url) else { return .pending }
        guard first.size == second.size, first.modificationDate == second.modificationDate else { return .pending }
        guard FileManager.default.isReadableFile(atPath: url.path) else { return .pending }
        return .ready
    }
}

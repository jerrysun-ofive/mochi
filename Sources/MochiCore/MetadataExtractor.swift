import Foundation
import UniformTypeIdentifiers

public struct MetadataExtractor: Sendable {
    public init() {}

    public func metadata(for url: URL) throws -> FileMetadata {
        let keys: Set<URLResourceKey> = [
            .nameKey, .fileSizeKey, .creationDateKey, .contentModificationDateKey,
            .isHiddenKey, .isRegularFileKey, .isSymbolicLinkKey,
        ]
        let values = try url.resourceValues(forKeys: keys)
        var contentTypeIdentifier: String?
        var tags: [String] = []
        var resourceID: Data?
        if let optional = try? url.resourceValues(forKeys: [.contentTypeKey]) {
            contentTypeIdentifier = optional.contentType?.identifier
        }
        if let optional = try? url.resourceValues(forKeys: [.tagNamesKey]) {
            tags = optional.tagNames ?? []
        }
        if let optional = try? url.resourceValues(forKeys: [.fileResourceIdentifierKey]),
           let identifier = optional.fileResourceIdentifier {
            resourceID = try? NSKeyedArchiver.archivedData(withRootObject: identifier, requiringSecureCoding: true)
        }
        let size = Int64(values.fileSize ?? 0)
        return FileMetadata(
            url: url,
            filename: values.name ?? url.lastPathComponent,
            fileExtension: url.pathExtension,
            contentTypeIdentifier: contentTypeIdentifier,
            size: size,
            creationDate: values.creationDate,
            modificationDate: values.contentModificationDate,
            finderTags: Set(tags),
            isHidden: values.isHidden ?? false,
            isRegularFile: values.isRegularFile ?? false,
            isSymbolicLink: values.isSymbolicLink ?? false,
            fingerprint: .init(size: size, modificationDate: values.contentModificationDate, resourceIdentifier: resourceID)
        )
    }
}

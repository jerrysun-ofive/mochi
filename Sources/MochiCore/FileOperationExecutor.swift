import Foundation

public actor FileOperationExecutor {
    private let journal: OperationJournal
    private let metadataExtractor: MetadataExtractor
    private let fileManager: FileManager

    public init(journal: OperationJournal, fileManager: FileManager = .default) {
        self.journal = journal
        self.fileManager = fileManager
        self.metadataExtractor = MetadataExtractor()
    }

    public func execute(_ proposal: ProposedOperation) async throws -> OperationRecord {
        guard !proposal.isExcluded, let requestedDestination = proposal.destinationURL else {
            throw ExecutorError.noExecutableDestination
        }
        guard proposal.source.isRegularFile, !proposal.source.isSymbolicLink else {
            throw ExecutorError.unsafeSource
        }
        guard !proposal.warnings.contains(.crossVolumeMoveUnsupported) else {
            throw ExecutorError.crossVolumeMoveUnsupported
        }
        let destination = collisionFreeURL(requestedDestination)
        var record = OperationRecord(
            ruleID: proposal.ruleID,
            sourceURL: proposal.source.url,
            destinationURL: destination,
            sourceFingerprint: proposal.source.fingerprint
        )
        try await journal.append(record)
        try await journal.transition(id: record.id, to: .prepared)

        do {
            try revalidateSource(record)
            try fileManager.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
            try await journal.transition(id: record.id, to: .executing)
            try fileManager.moveItem(at: proposal.source.url, to: destination)
            let destinationMetadata = try metadataExtractor.metadata(for: destination)
            try await journal.transition(id: record.id, to: .committed, destinationFingerprint: destinationMetadata.fingerprint)
        } catch {
            let sourceExists = fileManager.fileExists(atPath: proposal.source.url.path)
            let destinationExists = fileManager.fileExists(atPath: destination.path)
            let state: OperationState = (!sourceExists && destinationExists) ? .committed : ((sourceExists && !destinationExists) ? .failed : .needsReview)
            try? await journal.transition(id: record.id, to: state, failure: String(describing: error))
            if state != .committed { throw error }
        }
        guard let completed = await journal.record(id: record.id) else { throw ExecutorError.journalFailure }
        record = completed
        return record
    }

    public func undo(id: UUID) async throws -> OperationRecord {
        guard let record = await journal.record(id: id), record.state == .committed,
              let destination = record.destinationURL else { throw ExecutorError.notUndoable }
        guard fileManager.fileExists(atPath: destination.path), !fileManager.fileExists(atPath: record.sourceURL.path) else {
            throw ExecutorError.undoConflict
        }
        let current = try metadataExtractor.metadata(for: destination)
        guard current.fingerprint == record.destinationFingerprint else { throw ExecutorError.destinationChanged }
        try await journal.transition(id: id, to: .undoing)
        do {
            try fileManager.moveItem(at: destination, to: record.sourceURL)
            try await journal.transition(id: id, to: .undone)
        } catch {
            try? await journal.transition(id: id, to: .undoFailed, failure: String(describing: error))
            throw error
        }
        guard let completed = await journal.record(id: id) else { throw ExecutorError.journalFailure }
        return completed
    }

    public func recoverTransitionalOperations() async {
        for record in await journal.transitionalRecords() {
            let sourceExists = fileManager.fileExists(atPath: record.sourceURL.path)
            let destinationExists = record.destinationURL.map { fileManager.fileExists(atPath: $0.path) } ?? false
            do {
                if record.state == .undoing {
                    if sourceExists && !destinationExists { try await journal.transition(id: record.id, to: .undone) }
                    else { try await journal.transition(id: record.id, to: .needsReview) }
                } else if !sourceExists && destinationExists {
                    let fingerprint = try record.destinationURL.map(metadataExtractor.metadata)?.fingerprint
                    try await journal.transition(id: record.id, to: .committed, destinationFingerprint: fingerprint)
                } else if sourceExists && !destinationExists {
                    if record.state == .executing { try await journal.transition(id: record.id, to: .prepared) }
                } else {
                    try await journal.transition(id: record.id, to: .needsReview)
                }
            } catch {
                try? await journal.transition(id: record.id, to: .needsReview, failure: String(describing: error))
            }
        }
    }

    private func revalidateSource(_ record: OperationRecord) throws {
        let current = try metadataExtractor.metadata(for: record.sourceURL)
        guard current.fingerprint == record.sourceFingerprint else { throw ExecutorError.sourceChanged }
    }

    private func collisionFreeURL(_ requested: URL) -> URL {
        guard fileManager.fileExists(atPath: requested.path) else { return requested }
        let folder = requested.deletingLastPathComponent()
        let ext = requested.pathExtension
        let stem = requested.deletingPathExtension().lastPathComponent
        for index in 2...10_000 {
            let filename = ext.isEmpty ? "\(stem) (\(index))" : "\(stem) (\(index)).\(ext)"
            let candidate = folder.appendingPathComponent(filename)
            if !fileManager.fileExists(atPath: candidate.path) { return candidate }
        }
        return folder.appendingPathComponent("\(UUID().uuidString)-\(requested.lastPathComponent)")
    }
}

public enum ExecutorError: Error, Equatable {
    case noExecutableDestination, unsafeSource, sourceChanged, journalFailure
    case notUndoable, undoConflict, destinationChanged
    case crossVolumeMoveUnsupported
}

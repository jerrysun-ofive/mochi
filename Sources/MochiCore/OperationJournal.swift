import Foundation

public actor OperationJournal {
    private let fileURL: URL
    private var records: [UUID: OperationRecord]
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    public init(fileURL: URL) throws {
        self.fileURL = fileURL
        self.encoder = JSONEncoder()
        self.decoder = JSONDecoder()
        self.encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        self.encoder.dateEncodingStrategy = .iso8601
        self.decoder.dateDecodingStrategy = .iso8601
        if FileManager.default.fileExists(atPath: fileURL.path) {
            let data = try Data(contentsOf: fileURL)
            let decoded = try self.decoder.decode([OperationRecord].self, from: data)
            self.records = Dictionary(uniqueKeysWithValues: decoded.map { ($0.id, $0) })
        } else {
            self.records = [:]
        }
    }

    public func append(_ record: OperationRecord) throws {
        records[record.id] = record
        try persist()
    }

    public func transition(
        id: UUID,
        to state: OperationState,
        destinationFingerprint: FileFingerprint? = nil,
        failure: String? = nil
    ) throws {
        guard var record = records[id] else { throw JournalError.missingRecord }
        guard Self.allowedTransitions[record.state, default: []].contains(state) else {
            throw JournalError.invalidTransition(from: record.state, to: state)
        }
        record.state = state
        record.destinationFingerprint = destinationFingerprint ?? record.destinationFingerprint
        record.failureMessage = failure
        if [.committed, .failed, .needsReview, .undone, .undoFailed].contains(state) { record.completedAt = Date() }
        records[id] = record
        try persist()
    }

    public func record(id: UUID) -> OperationRecord? { records[id] }

    public func allRecords() -> [OperationRecord] {
        records.values.sorted { $0.createdAt > $1.createdAt }
    }

    public func transitionalRecords() -> [OperationRecord] {
        records.values.filter { [.prepared, .executing, .undoing].contains($0.state) }
    }

    private func persist() throws {
        let parent = fileURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)
        let data = try encoder.encode(allRecords())
        try data.write(to: fileURL, options: .atomic)
    }

    private static let allowedTransitions: [OperationState: Set<OperationState>] = [
        .planned: [.prepared, .failed, .needsReview],
        .prepared: [.executing, .failed, .needsReview],
        .executing: [.prepared, .committed, .failed, .needsReview],
        .committed: [.undoing],
        .undoing: [.undone, .undoFailed, .needsReview],
    ]
}

public enum JournalError: Error, Equatable {
    case missingRecord
    case invalidTransition(from: OperationState, to: OperationState)
}

import AppKit
import CryptoKit
import Foundation
import MochiAI
import MochiCore

enum AppSection: String, CaseIterable, Identifiable {
    case overview = "Overview"
    case folders = "Folders"
    case quickRules = "Quick Rules"
    case rules = "Rules"
    case review = "Review"
    case history = "History"
    case profile = "Profile"
    case settings = "Settings"

    static let workspace: [AppSection] = [.overview, .folders, .rules, .review, .history]

    var subsections: [AppSection] { self == .rules ? [.quickRules] : [] }

    var id: String { rawValue }
    var icon: String {
        switch self {
        case .overview: "gauge"
        case .folders: "folder"
        case .quickRules: "bolt.fill"
        case .rules: "list.bullet.rectangle"
        case .review: "checkmark.circle"
        case .history: "clock.arrow.circlepath"
        case .profile: "person.crop.circle"
        case .settings: "gearshape"
        }
    }
}

struct RuleEditorPresentation: Identifiable {
    let id = UUID()
    let rule: OrganizationRule?
}

@MainActor
final class AppModel: ObservableObject {
    @Published var selectedSection: AppSection? = .overview
    @Published var ruleEditor: RuleEditorPresentation?
    @Published var monitoringEnabled: Bool {
        didSet {
            UserDefaults.standard.set(monitoringEnabled, forKey: "monitoringEnabled")
            Task { await configureMonitoring() }
        }
    }
    @Published private(set) var grants: [FolderGrant] = []
    @Published private(set) var rules: [OrganizationRule] = []
    @Published private(set) var proposals: [ProposedOperation] = []
    @Published private(set) var history: [OperationRecord] = []
    @Published var notice: String?
    @Published var isBusy = false
    var onFilesSorted: ((Int) -> Void)?

    private let folderAccess: FolderAccessController
    private let journal: OperationJournal
    private let executor: FileOperationExecutor
    private let rulesURL: URL
    private var folderMonitor: FSEventsFolderMonitor?
    private var monitoredScanTask: Task<Void, Never>?
    private let makeAIOrchestrator: () -> HybridDecisionOrchestrator?
    private var aiSuggestions: [AIFileKey: AISuggestion] = [:]
    private var aiDeclinedFiles: Set<AIFileKey> = []

    static let aiFilesPerScan = 10

    init(
        supportRoot: URL? = nil,
        securityScopedBookmarks: Bool? = nil,
        aiOrchestrator: @escaping () -> HybridDecisionOrchestrator? = { BYOKConfiguration.makeOrchestrator() }
    ) {
        makeAIOrchestrator = aiOrchestrator
        monitoringEnabled = UserDefaults.standard.object(forKey: "monitoringEnabled") as? Bool ?? true
        let dataRoot = supportRoot ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Mochi", isDirectory: true)
        try? FileManager.default.createDirectory(at: dataRoot, withIntermediateDirectories: true)
        rulesURL = dataRoot.appendingPathComponent("rules.json")
        let accessURL = dataRoot.appendingPathComponent("folder-grants.json")
        let journalURL = dataRoot.appendingPathComponent("operation-journal.json")
        let useSecurityScope = securityScopedBookmarks ?? (ProcessInfo.processInfo.environment["APP_SANDBOX_CONTAINER_ID"] != nil)
        do {
            folderAccess = try FolderAccessController(storeURL: accessURL, securityScoped: useSecurityScope)
            journal = try OperationJournal(fileURL: journalURL)
        } catch {
            fatalError("Mochi could not initialize its local stores: \(error)")
        }
        executor = FileOperationExecutor(journal: journal)
        rules = Self.loadRules(from: rulesURL)
        Task { await refresh() }
    }

    var sourceGrants: [FolderGrant] { grants.filter { $0.roles.contains(.source) } }
    var destinationGrants: [FolderGrant] { grants.filter { $0.roles.contains(.destination) } }

    func refresh() async {
        do {
            grants = try await folderAccess.resolveAll()
            history = await journal.allRecords()
            await executor.recoverTransitionalOperations()
            history = await journal.allRecords()
            reportPreviouslySortedFilesOnce()
            await configureMonitoring()
        } catch {
            notice = "Could not load Mochi data: \(error.localizedDescription)"
        }
    }

    func chooseFolder(role: FolderRole) async {
        let panel = NSOpenPanel()
        panel.title = role == .source ? "Choose a folder for Mochi to watch" : "Choose an organization destination"
        panel.prompt = "Choose Folder"
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true
        guard panel.runModal() == .OK, let url = panel.url else { return }
        await authorizeFolder(url: url, role: role)
    }

    func authorizeFolder(url: URL, role: FolderRole) async {
        do {
            _ = try await folderAccess.add(url: url, roles: [role])
            grants = await folderAccess.allGrants()
            await configureMonitoring()
            notice = role == .source ? "Added \(url.lastPathComponent) as a watched folder." : "Added \(url.lastPathComponent) as a destination."
        } catch {
            notice = "Mochi could not authorize that folder: \(error.localizedDescription)"
        }
    }

    func removeFolder(_ grant: FolderGrant) async {
        do {
            try await folderAccess.remove(id: grant.id)
            grants = await folderAccess.allGrants()
            rules.removeAll { $0.sourceGrantIDs.contains(grant.id) || $0.destinationGrantID == grant.id }
            persistRules()
            await configureMonitoring()
            notice = "Removed \(grant.displayName) from Mochi. No files were deleted."
        } catch {
            notice = "Could not remove the folder: \(error.localizedDescription)"
        }
    }

    func setMonitoring(_ enabled: Bool, for grant: FolderGrant) async {
        do {
            try await folderAccess.update(id: grant.id, monitoringEnabled: enabled)
            grants = await folderAccess.allGrants()
            await configureMonitoring()
        } catch {
            notice = "Could not update the folder: \(error.localizedDescription)"
        }
    }

    func allowAsDestination(_ grantID: UUID) async throws {
        guard let grant = grants.first(where: { $0.id == grantID }), !grant.roles.contains(.destination) else { return }
        try await folderAccess.update(id: grantID, addingRoles: [.destination])
        grants = await folderAccess.allGrants()
    }

    func ensureDestinationSubfolder(grantID: UUID, relativePath: String) async throws -> Bool {
        guard let root = try await folderAccess.resolve(id: grantID),
              let folder = PathSafety.containedURL(root: root, relativePath: relativePath) else {
            throw QuickRuleFolderError.destinationUnavailable
        }
        var isDirectory: ObjCBool = false
        if FileManager.default.fileExists(atPath: folder.path, isDirectory: &isDirectory) {
            guard isDirectory.boolValue else { throw QuickRuleFolderError.pathIsNotFolder }
            return false
        }
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return true
    }

    func addRule(_ rule: OrganizationRule) {
        let issues = RuleValidator().validate(rule)
        guard issues.isEmpty else {
            notice = "The rule is not valid: \(issues.map(String.init(describing:)).joined(separator: ", "))"
            return
        }
        rules.append(rule)
        normalizePriorities()
        persistRules()
        notice = "Created rule “\(rule.name)”."
    }

    func updateRule(_ rule: OrganizationRule) {
        guard RuleValidator().validate(rule).isEmpty else {
            notice = "The edited rule is not valid."
            return
        }
        guard let index = rules.firstIndex(where: { $0.id == rule.id }) else { return }
        rules[index] = rule
        persistRules()
        notice = "Updated rule “\(rule.name)”."
    }

    func setRuleEnabled(_ enabled: Bool, id: UUID) {
        guard let index = rules.firstIndex(where: { $0.id == id }) else { return }
        rules[index].isEnabled = enabled
        persistRules()
    }

    func deleteRule(id: UUID) {
        rules.removeAll { $0.id == id }
        normalizePriorities()
        persistRules()
    }

    func moveRules(from offsets: IndexSet, to destination: Int) {
        rules.move(fromOffsets: offsets, toOffset: destination)
        normalizePriorities()
        persistRules()
    }

    func runNow(openReview: Bool = true) async {
        await scan(automatic: false, openReview: openReview)
    }

    func processMonitoredChangesNow() async {
        await scan(automatic: true)
    }

    private func scan(automatic: Bool, openReview: Bool = true) async {
        guard !isBusy else { return }
        guard !sourceGrants.isEmpty else {
            notice = "Add a watched folder before running Mochi."
            selectedSection = .folders
            return
        }
        var orchestrator: HybridDecisionOrchestrator?
        if !rules.contains(where: \.isEnabled) {
            orchestrator = makeAIOrchestrator()
            guard orchestrator != nil else {
                notice = "Create and enable at least one rule before running Mochi."
                selectedSection = .rules
                return
            }
        }
        isBusy = true
        defer { isBusy = false }
        do {
            var resolvedDestinations: [UUID: URL] = [:]
            for grant in destinationGrants {
                resolvedDestinations[grant.id] = try await folderAccess.resolve(id: grant.id)
            }
            let destinationSnapshot = resolvedDestinations
            let planner = OperationPlanner { destinationSnapshot[$0] }
            let engine = RuleEngine()
            let extractor = MetadataExtractor()
            var pending: [ProposedOperation] = []
            var unmatched: [FileMetadata] = []
            for grant in sourceGrants where grant.isMonitoringEnabled {
                guard let root = try await folderAccess.resolve(id: grant.id) else { continue }
                let urls = try FileManager.default.contentsOfDirectory(
                    at: root,
                    includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey],
                    options: [.skipsHiddenFiles, .skipsPackageDescendants]
                )
                for url in urls where !ReadinessProbe.temporaryExtensions.contains(url.pathExtension.lowercased()) {
                    guard let metadata = try? extractor.metadata(for: url) else { continue }
                    guard let match = engine.firstMatch(file: metadata, sourceGrantID: grant.id, rules: rules) else {
                        if metadata.isRegularFile, !metadata.isSymbolicLink, !metadata.isHidden { unmatched.append(metadata) }
                        continue
                    }
                    if case .move = match.rule.action.disposition {
                        let proposal = planner.plan(file: metadata, evaluation: match)
                        if proposal.destinationURL != nil { pending.append(proposal) }
                    }
                }
            }
            let ai = await aiProposals(for: unmatched, destinations: destinationSnapshot, planner: planner, orchestrator: orchestrator)
            pending.append(contentsOf: ai.proposals)
            let aiNote = ai.failure.map { " AI suggestions are unavailable because \($0)." } ?? ""
            if automatic {
                let existingSources = Set(proposals.map { $0.source.url.standardizedFileURL })
                let additions = pending.filter { !existingSources.contains($0.source.url.standardizedFileURL) }
                proposals.append(contentsOf: additions)
                if !additions.isEmpty {
                    notice = "Mochi found \(additions.count) new operation\(additions.count == 1 ? "" : "s") ready for review.\(aiNote)"
                } else if !aiNote.isEmpty {
                    notice = aiNote.trimmingCharacters(in: .whitespaces)
                }
            } else {
                proposals = pending
                if openReview { selectedSection = .review }
                notice = (pending.isEmpty ? "No files matched your enabled rules." : "Found \(pending.count) operation\(pending.count == 1 ? "" : "s") ready for review.") + aiNote
            }
        } catch {
            notice = "Organize Now failed: \(error.localizedDescription)"
        }
    }

    private func aiProposals(
        for files: [FileMetadata],
        destinations: [UUID: URL],
        planner: OperationPlanner,
        orchestrator preloaded: HybridDecisionOrchestrator?
    ) async -> (proposals: [ProposedOperation], failure: String?) {
        let pendingFiles = files.filter { !aiDeclinedFiles.contains(AIFileKey($0)) }
        guard !pendingFiles.isEmpty, !destinations.isEmpty else { return ([], nil) }
        let options = aiDestinationOptions(destinations)
        guard !options.isEmpty else { return ([], nil) }
        let references = Dictionary(uniqueKeysWithValues: options.map { ($0.candidate.id, $0) })
        let candidates = options.map(\.candidate)
        let parentIDs = Set(options.filter { $0.reference.relativeSubpath.isEmpty }.map(\.candidate.id))
        let candidateSetHash = SHA256.hash(data: Data(options.map { "\($0.reference.grantID)/\($0.reference.relativeSubpath)" }.joined(separator: "\n").utf8))
            .map { String(format: "%02x", $0) }.joined()
        let defaults = UserDefaults.standard
        let allowSnippets = defaults.bool(forKey: "allowTextSnippets")
        let allowFailover = defaults.bool(forKey: "allowProviderFailover")
        let policy = AIAutomationPolicy(minimumConfidence: 0.6, minimumMargin: 0.2)
        let extractor = LocalContentExtractor()

        var orchestrator = preloaded
        var consulted = 0
        var failure: String?
        var results: [ProposedOperation] = []
        for file in pendingFiles {
            let key = AIFileKey(file)
            if aiSuggestions[key] == nil {
                guard consulted < Self.aiFilesPerScan, failure == nil else { continue }
                if orchestrator == nil { orchestrator = makeAIOrchestrator() }
                guard let orchestrator else { return (results, nil) }
                consulted += 1
                let request = DestinationDecisionRequest(
                    file: extractor.envelope(for: file, allowBoundedText: allowSnippets),
                    candidates: candidates,
                    candidateSetHash: candidateSetHash
                )
                let outcome = await orchestrator.decide(request: request, authorizedParentIDs: parentIDs, policy: policy, allowProviderFailover: allowFailover)
                switch outcome {
                case .existingDestination(let id, _, let explanation):
                    guard let option = references[id] else { aiDeclinedFiles.insert(key); continue }
                    aiSuggestions[key] = AISuggestion(reference: option.reference, explanation: explanation ?? "Best match among your destinations: \(option.candidate.displayName).")
                case .proposedFolder(let parentID, let name, let explanation):
                    guard let parent = references[parentID]?.reference else { aiDeclinedFiles.insert(key); continue }
                    aiSuggestions[key] = AISuggestion(reference: DestinationReference(grantID: parent.grantID, relativeSubpath: name), explanation: "New folder “\(name)”: \(explanation)")
                case .review(.providerUnavailable, let explanation):
                    failure = explanation ?? "the provider could not be reached"
                    continue
                case .review:
                    aiDeclinedFiles.insert(key)
                    continue
                }
            }
            guard let suggestion = aiSuggestions[key] else { continue }
            let proposal = planner.plan(
                file: file,
                destination: suggestion.reference,
                reasons: [MatchReason(predicate: AISuggestion.reasonPredicate, matched: true, explanation: suggestion.explanation)]
            )
            guard let destination = proposal.destinationURL,
                  destination.deletingLastPathComponent().standardizedFileURL != file.url.deletingLastPathComponent().standardizedFileURL else { continue }
            results.append(proposal)
        }
        return (results, failure)
    }

    private func aiDestinationOptions(_ destinations: [UUID: URL]) -> [(candidate: DestinationCandidate, reference: DestinationReference)] {
        var options: [(candidate: DestinationCandidate, reference: DestinationReference)] = []
        for grant in destinationGrants {
            guard let root = destinations[grant.id] else { continue }
            options.append((
                DestinationCandidate(id: UUID(), displayName: grant.displayName, userDescription: grant.aiDescription),
                DestinationReference(grantID: grant.id)
            ))
            let children = (try? FileManager.default.contentsOfDirectory(
                at: root,
                includingPropertiesForKeys: [.isDirectoryKey, .isPackageKey],
                options: [.skipsHiddenFiles, .skipsPackageDescendants]
            )) ?? []
            for child in children.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
                let values = try? child.resourceValues(forKeys: [.isDirectoryKey, .isPackageKey])
                guard values?.isDirectory == true, values?.isPackage != true else { continue }
                options.append((
                    DestinationCandidate(id: UUID(), displayName: "\(grant.displayName)/\(child.lastPathComponent)"),
                    DestinationReference(grantID: grant.id, relativeSubpath: child.lastPathComponent)
                ))
            }
        }
        return Array(options.prefix(99))
    }

    func reject(_ proposal: ProposedOperation) {
        proposals.removeAll { $0.id == proposal.id }
        notice = "Skipped \(proposal.source.filename)."
    }

    func restore(_ proposal: ProposedOperation) {
        guard !proposals.contains(where: { $0.id == proposal.id }) else { return }
        proposals.insert(proposal, at: 0)
    }

    @discardableResult
    func approve(_ proposal: ProposedOperation) async -> OperationRecord? {
        do {
            let record = try await executor.execute(proposal)
            proposals.removeAll { $0.id == proposal.id }
            history = await journal.allRecords()
            onFilesSorted?(1)
            notice = "Moved \(proposal.source.filename)."
            return record
        } catch {
            notice = "Could not move \(proposal.source.filename): \(error.localizedDescription)"
            return nil
        }
    }

    func approveAll() async {
        for proposal in proposals { await approve(proposal) }
    }

    func undo(_ record: OperationRecord) async {
        do {
            _ = try await executor.undo(id: record.id)
            history = await journal.allRecords()
            notice = "Restored \(record.sourceURL.lastPathComponent)."
        } catch {
            notice = "Could not undo that operation: \(error.localizedDescription)"
        }
    }

    private func reportPreviouslySortedFilesOnce() {
        guard let onFilesSorted, !UserDefaults.standard.bool(forKey: "usage.historyCounted") else { return }
        UserDefaults.standard.set(true, forKey: "usage.historyCounted")
        onFilesSorted(history.filter { $0.state == .committed || $0.state == .undone }.count)
    }

    private func normalizePriorities() {
        for index in rules.indices { rules[index].priority = index }
    }

    private func configureMonitoring() async {
        folderMonitor?.stop()
        folderMonitor = nil
        monitoredScanTask?.cancel()
        guard monitoringEnabled else { return }
        do {
            var urls: [URL] = []
            for grant in sourceGrants where grant.isMonitoringEnabled {
                if let url = try await folderAccess.resolve(id: grant.id) { urls.append(url) }
            }
            guard !urls.isEmpty else { return }
            let monitor = FSEventsFolderMonitor(urls: urls) { [weak self] events in
                guard events.contains(where: { !$0.path.isEmpty }) else { return }
                Task { @MainActor [weak self] in self?.scheduleMonitoredScan() }
            }
            try monitor.start()
            folderMonitor = monitor
        } catch {
            notice = "Folder monitoring could not start: \(error.localizedDescription)"
        }
    }

    private func scheduleMonitoredScan() {
        monitoredScanTask?.cancel()
        monitoredScanTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(1))
            guard !Task.isCancelled else { return }
            await self?.processMonitoredChangesNow()
        }
    }

    private func persistRules() {
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(rules).write(to: rulesURL, options: .atomic)
        } catch {
            notice = "Could not save rules: \(error.localizedDescription)"
        }
    }

    private static func loadRules(from url: URL) -> [OrganizationRule] {
        guard let data = try? Data(contentsOf: url), let rules = try? JSONDecoder().decode([OrganizationRule].self, from: data) else { return [] }
        return rules.sorted { $0.priority < $1.priority }
    }
}

private struct AIFileKey: Hashable {
    let path: String
    let fingerprint: FileFingerprint

    init(_ file: FileMetadata) {
        path = file.url.standardizedFileURL.path
        fingerprint = file.fingerprint
    }
}

struct AISuggestion {
    static let reasonPredicate = "aiSuggestion"

    let reference: DestinationReference
    let explanation: String
}

extension ProposedOperation {
    var aiExplanation: String? {
        reasons.first(where: { $0.predicate == AISuggestion.reasonPredicate })?.explanation
    }
}

private enum QuickRuleFolderError: LocalizedError {
    case destinationUnavailable
    case pathIsNotFolder

    var errorDescription: String? {
        switch self {
        case .destinationUnavailable: "The selected destination is no longer available."
        case .pathIsNotFolder: "A file already exists where the destination folder should be."
        }
    }
}

private extension OrganizationRule {
    var destinationGrantID: UUID? {
        guard case .move(let destination) = action.disposition else { return nil }
        return destination.grantID
    }
}

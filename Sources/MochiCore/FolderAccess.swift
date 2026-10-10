import Foundation

public enum FolderRole: String, Codable, Hashable, Sendable { case source, destination }
public enum PermissionState: String, Codable, Sendable { case available, stale, unavailable }

public struct FolderGrant: Codable, Identifiable, Sendable {
    public let id: UUID
    public var displayName: String
    public var roles: Set<FolderRole>
    public var bookmarkData: Data
    public var lastResolvedPathHint: String?
    public var permissionState: PermissionState
    public var isMonitoringEnabled: Bool
    public var isAIEligible: Bool
    public var aiDescription: String?

    public init(
        id: UUID = UUID(),
        displayName: String,
        roles: Set<FolderRole>,
        bookmarkData: Data,
        lastResolvedPathHint: String?,
        permissionState: PermissionState = .available,
        isMonitoringEnabled: Bool = true,
        isAIEligible: Bool = false,
        aiDescription: String? = nil
    ) {
        self.id = id
        self.displayName = displayName
        self.roles = roles
        self.bookmarkData = bookmarkData
        self.lastResolvedPathHint = lastResolvedPathHint
        self.permissionState = permissionState
        self.isMonitoringEnabled = isMonitoringEnabled
        self.isAIEligible = isAIEligible
        self.aiDescription = aiDescription
    }
}

public actor FolderAccessController {
    private let storeURL: URL
    private let securityScoped: Bool
    private var grants: [UUID: FolderGrant] = [:]
    private var activeURLs: [UUID: URL] = [:]

    public init(storeURL: URL, securityScoped: Bool = true) throws {
        self.storeURL = storeURL
        self.securityScoped = securityScoped
        if FileManager.default.fileExists(atPath: storeURL.path) {
            let data = try Data(contentsOf: storeURL)
            let values = try JSONDecoder().decode([FolderGrant].self, from: data)
            grants = Dictionary(uniqueKeysWithValues: values.map { ($0.id, $0) })
        }
    }

    deinit {
        for url in activeURLs.values { url.stopAccessingSecurityScopedResource() }
    }

    public func add(url: URL, roles: Set<FolderRole>) throws -> FolderGrant {
        let options: URL.BookmarkCreationOptions = securityScoped ? [.withSecurityScope] : []
        let bookmark = try url.bookmarkData(options: options, includingResourceValuesForKeys: nil, relativeTo: nil)
        let grant = FolderGrant(displayName: url.lastPathComponent, roles: roles, bookmarkData: bookmark, lastResolvedPathHint: url.path)
        grants[grant.id] = grant
        try persist()
        return grant
    }

    public func resolveAll() throws -> [FolderGrant] {
        for id in grants.keys { _ = try resolve(id: id) }
        try persist()
        return grants.values.sorted { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }
    }

    public func resolve(id: UUID) throws -> URL? {
        guard var grant = grants[id] else { return nil }
        if let active = activeURLs[id] { return active }
        var stale = false
        do {
            let options: URL.BookmarkResolutionOptions = securityScoped ? [.withSecurityScope] : []
            let url = try URL(resolvingBookmarkData: grant.bookmarkData, options: options, relativeTo: nil, bookmarkDataIsStale: &stale)
            guard !securityScoped || url.startAccessingSecurityScopedResource() else {
                grant.permissionState = .unavailable
                grants[id] = grant
                return nil
            }
            activeURLs[id] = url
            grant.permissionState = stale ? .stale : .available
            grant.lastResolvedPathHint = url.path
            if stale {
                let creationOptions: URL.BookmarkCreationOptions = securityScoped ? [.withSecurityScope] : []
                grant.bookmarkData = try url.bookmarkData(options: creationOptions, includingResourceValuesForKeys: nil, relativeTo: nil)
                grant.permissionState = .available
            }
            grants[id] = grant
            return url
        } catch {
            grant.permissionState = .unavailable
            grants[id] = grant
            return nil
        }
    }

    public func remove(id: UUID) throws {
        activeURLs.removeValue(forKey: id)?.stopAccessingSecurityScopedResource()
        grants.removeValue(forKey: id)
        try persist()
    }

    public func update(
        id: UUID,
        monitoringEnabled: Bool? = nil,
        aiEligible: Bool? = nil,
        aiDescription: String? = nil,
        addingRoles: Set<FolderRole> = []
    ) throws {
        guard var grant = grants[id] else { return }
        grant.roles.formUnion(addingRoles)
        if let monitoringEnabled { grant.isMonitoringEnabled = monitoringEnabled }
        if let aiEligible { grant.isAIEligible = aiEligible }
        if let aiDescription { grant.aiDescription = aiDescription.isEmpty ? nil : aiDescription }
        grants[id] = grant
        try persist()
    }

    public func allGrants() -> [FolderGrant] { Array(grants.values) }

    private func persist() throws {
        try FileManager.default.createDirectory(at: storeURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        let data = try JSONEncoder().encode(Array(grants.values))
        try data.write(to: storeURL, options: .atomic)
    }
}

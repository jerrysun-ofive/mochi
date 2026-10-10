import Foundation

public enum ValidationIssue: Error, Equatable, Sendable {
    case unsupportedSchema(Int)
    case emptyName
    case emptyConditions
    case negativeSize
    case invalidDestinationPath
    case unsupportedRenameToken(String)
    case unsafeRenameTemplate
}

public struct RuleValidator: Sendable {
    public init() {}

    public func validate(_ rule: OrganizationRule) -> [ValidationIssue] {
        var issues: [ValidationIssue] = []
        if rule.schemaVersion != 1 { issues.append(.unsupportedSchema(rule.schemaVersion)) }
        if rule.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { issues.append(.emptyName) }
        if rule.match.predicates.isEmpty { issues.append(.emptyConditions) }
        for predicate in rule.match.predicates {
            if case .size(_, let bytes) = predicate, bytes < 0 { issues.append(.negativeSize) }
        }
        if case .move(let destination) = rule.action.disposition,
           !PathSafety.isSafeRelativePath(destination.relativeSubpath) {
            issues.append(.invalidDestinationPath)
        }
        if let template = rule.action.renameTemplate {
            issues.append(contentsOf: validateTemplate(template))
        }
        return issues
    }

    private func validateTemplate(_ template: String) -> [ValidationIssue] {
        if template.isEmpty || template.contains("/") || template.contains(":") || template.contains("\0") {
            return [.unsafeRenameTemplate]
        }
        let allowed = ["{name}", "{ext}", "{created:yyyy-MM-dd}", "{modified:yyyy-MM-dd}"]
        let pattern = #"\{[^}]+\}"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [.unsafeRenameTemplate] }
        let range = NSRange(template.startIndex..., in: template)
        return regex.matches(in: template, range: range).compactMap { match in
            guard let swiftRange = Range(match.range, in: template) else { return nil }
            let token = String(template[swiftRange])
            return allowed.contains(token) ? nil : .unsupportedRenameToken(token)
        }
    }
}

public enum PathSafety {
    public static func isSafeRelativePath(_ path: String) -> Bool {
        if path.isEmpty { return true }
        if path.hasPrefix("/") || path.contains("\0") { return false }
        let components = NSString(string: path).pathComponents
        return !components.contains("..") && !components.contains("~")
    }

    public static func containedURL(root: URL, relativePath: String) -> URL? {
        guard isSafeRelativePath(relativePath) else { return nil }
        let standardizedRoot = root.standardizedFileURL
        let candidate = standardizedRoot.appendingPathComponent(relativePath).standardizedFileURL
        let resolvedRoot = standardizedRoot.resolvingSymlinksInPath()
        let rootPath = resolvedRoot.path.hasSuffix("/") ? resolvedRoot.path : resolvedRoot.path + "/"
        var resolvedCursor = resolvedRoot
        for component in NSString(string: relativePath).pathComponents where component != "/" && component != "." {
            resolvedCursor = resolvedCursor.appendingPathComponent(component).resolvingSymlinksInPath()
            guard resolvedCursor == resolvedRoot || resolvedCursor.path.hasPrefix(rootPath) else { return nil }
        }
        return candidate
    }
}

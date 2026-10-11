import MochiCore
import MochiAI
import SwiftUI

struct DashboardView: View {
    @ObservedObject var model: AppModel
    @ObservedObject var account: AccountModel

    var body: some View {
        NavigationSplitView {
            sidebar
                .navigationSplitViewColumnWidth(min: 200, ideal: 220, max: 280)
        } detail: {
            detail.frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .sheet(item: $model.ruleEditor) { presentation in
            RuleEditorView(existing: presentation.rule, sourceGrants: model.sourceGrants, destinationGrants: model.destinationGrants) { rule in
                if presentation.rule == nil { model.addRule(rule) } else { model.updateRule(rule) }
                model.ruleEditor = nil
            } onCancel: {
                model.ruleEditor = nil
            }
        }
        .alert("Mochi", isPresented: Binding(
            get: { model.notice != nil },
            set: { if !$0 { model.notice = nil } }
        )) {
            Button("OK") { model.notice = nil }
        } message: {
            Text(model.notice ?? "")
        }
    }

    private var sidebar: some View {
        List(selection: $model.selectedSection) {
            ForEach(AppSection.workspace) { section in
                sidebarRow(section)
                ForEach(section.subsections) { sidebarRow($0) }
            }
        }
        .listStyle(.sidebar)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            VStack(spacing: 8) {
                accountFooter
                monitoringFooter
            }
            .padding(.horizontal, 10)
            .padding(.bottom, 10)
        }
    }

    private func sidebarRow(_ section: AppSection) -> some View {
        Label(section.rawValue, systemImage: section.icon)
            .badge(section == .review ? model.proposals.count : 0)
            .tag(section)
            .accessibilityIdentifier("sidebar.\(section.rawValue.lowercased())")
    }

    @ViewBuilder private var detail: some View {
        switch model.selectedSection ?? .overview {
        case .overview: OverviewView(model: model, createRule: newRule)
        case .folders: FoldersView(model: model)
        case .quickRules: QuickRulesView(model: model)
        case .rules: RulesView(model: model, createRule: newRule, editRule: editRule)
        case .review: ReviewView(model: model)
        case .history: HistoryView(model: model)
        case .profile: ProfileView(account: account)
        case .settings: SettingsView(model: model, embedded: true)
        }
    }

    private var accountFooter: some View {
        HStack(spacing: 4) {
            Button { model.selectedSection = .profile } label: {
                HStack(spacing: 8) {
                    AccountAvatar(account: account, size: 26)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(account.isSignedIn ? account.displayName : "Sign in")
                            .font(.callout.weight(.medium))
                            .lineLimit(1)
                        Text(account.isSignedIn ? "View profile" : "Create an account")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 0)
                }
                .padding(6)
                .background(sidebarHighlight(for: .profile))
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Profile")
            .accessibilityIdentifier("sidebar.profile")

            Button { model.selectedSection = .settings } label: {
                Image(systemName: "gearshape")
                    .font(.system(size: 15))
                    .frame(width: 32, height: 32)
                    .background(sidebarHighlight(for: .settings))
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Settings")
            .accessibilityLabel("Settings")
            .accessibilityIdentifier("sidebar.settings")
        }
        .padding(.bottom, 4)
    }

    private func sidebarHighlight(for section: AppSection) -> some View {
        RoundedRectangle(cornerRadius: 7)
            .fill(model.selectedSection == section ? Color.accentColor.opacity(0.16) : .clear)
    }

    private var monitoringFooter: some View {
        let watchedCount = model.sourceGrants.filter(\.isMonitoringEnabled).count
        return HStack(spacing: 10) {
            ZStack {
                Circle()
                    .fill((model.monitoringEnabled ? Color.green : Color.orange).opacity(0.18))
                    .frame(width: 26, height: 26)
                Image(systemName: model.monitoringEnabled ? "eye.fill" : "pause.fill")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(model.monitoringEnabled ? Color.green : Color.orange)
            }
            VStack(alignment: .leading, spacing: 1) {
                Text(model.monitoringEnabled ? "Monitoring" : "Paused")
                    .font(.callout.weight(.medium))
                Text(model.monitoringEnabled
                     ? "\(watchedCount) folder\(watchedCount == 1 ? "" : "s") watched"
                     : "New files won’t be found")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
            Toggle("Monitoring", isOn: $model.monitoringEnabled)
                .toggleStyle(.switch)
                .controlSize(.mini)
                .labelsHidden()
                .help(model.monitoringEnabled ? "Pause monitoring" : "Resume monitoring")
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 7)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.secondary.opacity(0.08)))
        .padding(.bottom, 10)
        .animation(.easeInOut(duration: 0.15), value: model.monitoringEnabled)
    }

    private func newRule() { model.ruleEditor = RuleEditorPresentation(rule: nil) }
    private func editRule(_ rule: OrganizationRule) { model.ruleEditor = RuleEditorPresentation(rule: rule) }
}

private struct QuickRulesView: View {
    @ObservedObject var model: AppModel
    @State private var sourceID: UUID?
    @State private var destinationID: UUID?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            PageHeader(title: "Quick Rules", subtitle: "Add useful local rules in one click, then review every move as usual.") { EmptyView() }
            if model.sourceGrants.isEmpty {
                EmptyState(
                    icon: "bolt.badge.clock",
                    title: "Add a watched folder first",
                    detail: "Quick Rules sort files from a watched folder, such as Downloads.",
                    buttonTitle: "Open Folders"
                ) { model.selectedSection = .folders }
            } else {
                HStack(spacing: 10) {
                    Text("Watch").foregroundStyle(.secondary)
                    Menu(sourceName) {
                        Button("All watched folders") { sourceID = nil }
                        ForEach(model.sourceGrants) { grant in Button(grant.displayName) { sourceID = grant.id } }
                    }
                    .fixedSize()
                    .accessibilityLabel("Watch")
                    Text("Destination").foregroundStyle(.secondary).padding(.leading, 8)
                    Menu(destinationName) {
                        Button("Inside the watched folder") { destinationID = nil }
                        let others = model.destinationGrants.filter { grant in !model.sourceGrants.contains { $0.id == grant.id } }
                        if !others.isEmpty {
                            Divider()
                            ForEach(others) { grant in Button(grant.displayName) { destinationID = grant.id } }
                        }
                    }
                    .fixedSize()
                    .accessibilityLabel("Destination")
                    Spacer()
                }

                if destinationID == nil && insideSourceID == nil {
                    Label("Choose which watched folder to sort so Mochi knows where to create the new folders.", systemImage: "info.circle")
                        .font(.callout).foregroundStyle(.secondary)
                }

                ScrollView {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 270), spacing: 14)], spacing: 14) {
                        ForEach(orderedTemplates) { template in
                            QuickRuleCard(
                                template: template,
                                isAdded: model.rules.contains(where: { $0.name == template.name }),
                                targetFolderName: targetFolderName
                            ) {
                                add(template)
                            }
                        }
                    }
                    .padding(.vertical, 2)
                }
            }
        }
        .padding(28)
        .onChange(of: model.destinationGrants.map(\.id)) { ids in
            if let destinationID, !ids.contains(destinationID) { self.destinationID = nil }
        }
    }

    private var insideSourceID: UUID? {
        sourceID ?? (model.sourceGrants.count == 1 ? model.sourceGrants.first?.id : nil)
    }

    private var targetFolderName: String? {
        if let destinationID {
            return model.destinationGrants.first(where: { $0.id == destinationID })?.displayName
        }
        guard let insideSourceID else { return nil }
        return model.sourceGrants.first(where: { $0.id == insideSourceID })?.displayName
    }

    private func add(_ template: QuickRuleTemplate) {
        Task {
            if let destinationID {
                _ = await model.addQuickRule(template, sourceGrantID: sourceID, destinationGrantID: destinationID)
            } else if let insideSourceID {
                _ = await model.addQuickRuleInsideWatchedFolder(template, sourceGrantID: insideSourceID)
            }
        }
    }

    private var sourceName: String {
        guard let sourceID else { return "All watched folders" }
        return model.sourceGrants.first(where: { $0.id == sourceID })?.displayName ?? "Choose a watched folder"
    }

    private var destinationName: String {
        guard let destinationID else { return "Inside the watched folder" }
        return model.destinationGrants.first(where: { $0.id == destinationID })?.displayName ?? "Inside the watched folder"
    }

    private var orderedTemplates: [QuickRuleTemplate] {
        let addedNames = Set(model.rules.map(\.name))
        return QuickRuleTemplate.builtIns.filter { !addedNames.contains($0.name) }
            + QuickRuleTemplate.builtIns.filter { addedNames.contains($0.name) }
    }
}

private struct QuickRuleCard: View {
    let template: QuickRuleTemplate
    let isAdded: Bool
    let targetFolderName: String?
    let add: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: template.systemImage).font(.title2).foregroundStyle(.tint)
                Text(template.name).font(.headline)
                Spacer()
            }
            Text(template.detail).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            if let targetFolderName {
                Label("\(targetFolderName) / \(template.subfolder)", systemImage: "folder.badge.plus")
                    .font(.caption.weight(.medium)).foregroundStyle(.secondary)
                    .help("Mochi will create (or reuse) the “\(template.subfolder)” folder inside \(targetFolderName).")
            }
            Spacer(minLength: 2)
            Button(isAdded ? "Added" : "Add Rule", action: add)
                .buttonStyle(.borderedProminent)
                .disabled(isAdded || targetFolderName == nil)
                .accessibilityIdentifier("quickRule.\(template.id)")
        }
        .padding(16)
        .frame(maxWidth: .infinity, minHeight: 158, alignment: .leading)
        .cardStyle()
    }
}

struct OverviewView: View {
    @ObservedObject var model: AppModel
    let createRule: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("A little helper for your messy files.").font(.largeTitle.bold())
                    Text(summary).foregroundStyle(.secondary)
                }
                HStack(spacing: 14) {
                    if isSetUp {
                        MetricCard(title: "Sorted this week", value: "\(sortedThisWeek)", icon: "tray.and.arrow.down") {
                            model.selectedSection = .history
                        }
                    } else {
                        MetricCard(title: "Watched folders", value: "\(model.sourceGrants.count)", icon: "folder.badge.gearshape") {
                            model.selectedSection = .folders
                        }
                    }
                    MetricCard(title: "Enabled rules", value: "\(model.rules.filter(\.isEnabled).count)", icon: "list.bullet.rectangle") {
                        model.selectedSection = .rules
                    }
                    MetricCard(title: "Needs review", value: "\(model.proposals.count)", icon: "checkmark.circle") {
                        model.selectedSection = .review
                    }
                }
                if isSetUp {
                    if !model.proposals.isEmpty { reviewBanner }
                    recentActivity
                } else {
                    quickStart
                }
            }
            .padding(28)
        }
    }

    private var isSetUp: Bool { !model.sourceGrants.isEmpty && !model.destinationGrants.isEmpty && !model.rules.isEmpty }

    private var sortedRecords: [OperationRecord] {
        model.history
            .filter { $0.state == .committed || $0.state == .undone }
            .sorted { ($0.completedAt ?? $0.createdAt) > ($1.completedAt ?? $1.createdAt) }
    }

    private var sortedThisWeek: Int {
        let start = Date().addingTimeInterval(-7 * 24 * 60 * 60)
        return sortedRecords.filter { $0.state == .committed && ($0.completedAt ?? $0.createdAt) >= start }.count
    }

    private var reviewBanner: some View {
        HStack(spacing: 12) {
            Image(systemName: "tray.full.fill").font(.title2).foregroundStyle(Color.accentColor)
            VStack(alignment: .leading, spacing: 2) {
                Text("\(model.proposals.count) \(model.proposals.count == 1 ? "file is" : "files are") ready for review").font(.headline)
                Text("Nothing moves until you approve it.").font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Button("Review") { model.selectedSection = .review }.buttonStyle(.borderedProminent)
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.accentColor.opacity(0.1)))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Color.accentColor.opacity(0.3)))
    }

    private var recentActivity: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Recent activity").font(.headline)
                Spacer()
                if !sortedRecords.isEmpty {
                    Button("View All") { model.selectedSection = .history }.buttonStyle(.borderless)
                }
            }
            if sortedRecords.isEmpty {
                Text("Nothing sorted yet. Run Organize Now to find files that match your rules.")
                    .font(.callout).foregroundStyle(.secondary)
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(sortedRecords.prefix(5).enumerated()), id: \.element.id) { index, record in
                        RecentActivityRow(record: record) { Task { await model.undo(record) } }
                        if index < min(sortedRecords.count, 5) - 1 { Divider() }
                    }
                }
            }
        }
        .padding(16)
        .cardStyle()
    }

    private var quickStart: some View {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Quick start").font(.headline)
                    VStack(alignment: .leading, spacing: 14) {
                        QuickStartRow(number: 1, title: "Choose a watched folder", complete: !model.sourceGrants.isEmpty) {
                            Task { await model.chooseFolder(role: .source) }
                        }
                        Divider()
                        QuickStartRow(number: 2, title: "Choose an organization destination", complete: !model.destinationGrants.isEmpty) {
                            Task { await model.chooseFolder(role: .destination) }
                        }
                        Divider()
                        QuickStartRow(number: 3, title: "Create your first rule", complete: !model.rules.isEmpty) {
                            model.selectedSection = .quickRules
                        }
                    }
                }
                .padding(16)
                .cardStyle()
    }

    private var summary: String {
        if !model.monitoringEnabled { return "Monitoring is paused. Existing files will stay where they are." }
        if model.sourceGrants.isEmpty { return "Start by granting access to a folder. Mochi never scans outside folders you choose." }
        return "Ready to organize with local, reviewable rules."
    }
}

private struct MetricCard: View {
    let title: String
    let value: String
    let icon: String
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .top) {
                    Image(systemName: icon)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Color.accentColor)
                        .frame(width: 28, height: 28)
                        .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(Color.accentColor.opacity(0.14)))
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.tertiary)
                        .opacity(isHovered ? 1 : 0)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(value)
                        .font(.system(size: 26, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                    Text(title).font(.callout).foregroundStyle(.secondary)
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .cardStyle(highlighted: isHovered)
            .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .animation(.easeInOut(duration: 0.12), value: isHovered)
        .accessibilityHint("Opens \(title)")
    }
}

private struct RecentActivityRow: View {
    let record: OperationRecord
    let undo: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(nsImage: NSWorkspace.shared.icon(forFile: (record.state == .committed ? record.destinationURL : nil)?.path ?? record.sourceURL.path))
                .resizable()
                .frame(width: 24, height: 24)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text(record.destinationURL?.lastPathComponent ?? record.sourceURL.lastPathComponent)
                    .lineLimit(1).truncationMode(.middle)
                MoveRoute(from: record.sourceURL.deletingLastPathComponent(), to: record.destinationURL?.deletingLastPathComponent(), compact: true)
            }
            Spacer()
            Text((record.completedAt ?? record.createdAt).formatted(.relative(presentation: .named)))
                .font(.caption).foregroundStyle(.secondary)
            if record.state == .committed {
                Button("Undo", action: undo).buttonStyle(.borderless)
            } else {
                Text("Undone").font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 7)
    }
}

private struct QuickStartRow: View {
    let number: Int
    let title: String
    let complete: Bool
    let action: () -> Void
    var body: some View {
        HStack {
            Image(systemName: complete ? "checkmark.circle.fill" : "\(number).circle")
                .foregroundStyle(complete ? Color.green : Color.secondary)
            Text(title)
            Spacer()
            Button(complete ? "Change" : "Set Up", action: action)
        }
    }
}

private struct FoldersView: View {
    @ObservedObject var model: AppModel

    private var standaloneDestinations: [FolderGrant] {
        model.destinationGrants.filter { !$0.roles.contains(.source) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            PageHeader(title: "Folders", subtitle: "Each watched folder shows where Mochi sorts its files. Mochi only touches folders you authorize.") {
                Menu {
                    Button("Watched Folder…") { Task { await model.chooseFolder(role: .source) } }
                    Button("Destination Folder…") { Task { await model.chooseFolder(role: .destination) } }
                } label: { Label("Add Folder", systemImage: "plus") }
            }
            if model.grants.isEmpty {
                EmptyState(icon: "folder.badge.plus", title: "No authorized folders", detail: "Add a watched folder, such as Downloads, to begin.")
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        if model.sourceGrants.isEmpty {
                            Text("Add a watched folder so Mochi has something to sort.")
                                .foregroundStyle(.secondary)
                        }
                        ForEach(model.sourceGrants) { grant in
                            WatchedFolderCard(model: model, grant: grant)
                        }
                        if !standaloneDestinations.isEmpty {
                            DestinationAccessCard(model: model, grants: standaloneDestinations)
                                .padding(.top, 8)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.bottom, 4)
                }
            }
        }.padding(28)
    }
}

private struct SortTarget: Identifiable {
    let url: URL
    let displayPath: String
    let isInsideWatchedFolder: Bool
    var rules: [OrganizationRule]
    var id: String { url.path }
}

private struct WatchedFolderCard: View {
    @ObservedObject var model: AppModel
    let grant: FolderGrant

    private var targets: [SortTarget] {
        guard let sourcePath = grant.lastResolvedPathHint else { return [] }
        var byPath: [String: SortTarget] = [:]
        for rule in model.rules where rule.sourceGrantIDs.isEmpty || rule.sourceGrantIDs.contains(grant.id) {
            guard case .move(let destination) = rule.action.disposition,
                  let root = model.destinationGrants.first(where: { $0.id == destination.grantID })?.lastResolvedPathHint else { continue }
            var url = URL(fileURLWithPath: root, isDirectory: true)
            if !destination.relativeSubpath.isEmpty {
                url.appendPathComponent(destination.relativeSubpath, isDirectory: true)
            }
            let path = url.standardizedFileURL.path
            if byPath[path] == nil {
                let inside = path.hasPrefix(sourcePath + "/")
                byPath[path] = SortTarget(
                    url: url,
                    displayPath: inside ? String(path.dropFirst(sourcePath.count + 1)) : abbreviated(path),
                    isInsideWatchedFolder: inside,
                    rules: []
                )
            }
            byPath[path]?.rules.append(rule)
        }
        return byPath.values.sorted {
            if $0.isInsideWatchedFolder != $1.isInsideWatchedFolder { return $0.isInsideWatchedFolder }
            return $0.displayPath.localizedStandardCompare($1.displayPath) == .orderedAscending
        }
    }

    var body: some View {
        let targets = targets
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                Image(systemName: "folder.fill.badge.gearshape")
                    .font(.title2)
                    .foregroundStyle(grant.isMonitoringEnabled ? Color.accentColor : Color.secondary)
                VStack(alignment: .leading, spacing: 2) {
                    Text(grant.displayName).font(.headline)
                    Text(grant.lastResolvedPathHint.map(abbreviated) ?? "Permission unavailable")
                        .font(.caption).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                }
                Spacer()
                Toggle("Watch", isOn: Binding(
                    get: { grant.isMonitoringEnabled },
                    set: { value in Task { await model.setMonitoring(value, for: grant) } }
                ))
                .toggleStyle(.switch)
                .controlSize(.small)
                Button(role: .destructive) { Task { await model.removeFolder(grant) } } label: { Image(systemName: "trash") }
                    .buttonStyle(.borderless)
                    .accessibilityLabel("Remove \(grant.displayName)")
                    .accessibilityIdentifier("folder.remove.\(grant.id.uuidString)")
                    .help("Stop watching and remove authorization. No files are deleted.")
            }

            if targets.isEmpty {
                HStack {
                    Text("No rules sort this folder yet.").font(.callout).foregroundStyle(.secondary)
                    Spacer()
                    Button("Add Quick Rules") { model.selectedSection = .quickRules }
                        .buttonStyle(.borderless)
                }
                .padding(.leading, 36)
            } else {
                VStack(alignment: .leading, spacing: 0) {
                    Text("SORTS INTO")
                        .font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
                        .padding(.leading, 14).padding(.bottom, 4)
                    ForEach(Array(targets.enumerated()), id: \.element.id) { index, target in
                        SortTargetRow(target: target, isLast: index == targets.count - 1)
                    }
                }
                .padding(.leading, 22)
            }
        }
        .padding(16)
        .cardStyle()
        .accessibilityElement(children: .contain)
    }
}

private struct SortTargetRow: View {
    let target: SortTarget
    let isLast: Bool

    var body: some View {
        HStack(alignment: .center, spacing: 8) {
            TreeConnector(isLast: isLast)
            Image(systemName: target.isInsideWatchedFolder ? "folder.fill" : "folder.fill.badge.person.crop")
                .foregroundStyle(Color.accentColor)
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 4) {
                    Text(target.displayPath).font(.callout.weight(.medium)).lineLimit(1).truncationMode(.head)
                    if !target.isInsideWatchedFolder {
                        Image(systemName: "arrow.up.forward").font(.caption2).foregroundStyle(.secondary)
                            .help("Outside the watched folder")
                    }
                }
                Text(target.rules.map { $0.isEnabled ? $0.name : "\($0.name) (off)" }.joined(separator: ", "))
                    .font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            .opacity(target.rules.contains(where: \.isEnabled) ? 1 : 0.55)
            Spacer()
            Button {
                NSWorkspace.shared.activateFileViewerSelecting([target.url])
            } label: { Image(systemName: "magnifyingglass") }
                .buttonStyle(.borderless)
                .help("Show in Finder")
        }
        .frame(minHeight: 38)
        .help(target.url.path)
    }
}

private struct TreeConnector: View {
    let isLast: Bool

    var body: some View {
        GeometryReader { proxy in
            Path { path in
                let midY = proxy.size.height / 2
                path.move(to: CGPoint(x: 1, y: 0))
                path.addLine(to: CGPoint(x: 1, y: isLast ? midY : proxy.size.height))
                path.move(to: CGPoint(x: 1, y: midY))
                path.addLine(to: CGPoint(x: proxy.size.width, y: midY))
            }
            .stroke(Color.secondary.opacity(0.35), lineWidth: 1)
        }
        .frame(width: 14)
    }
}

private struct DestinationAccessCard: View {
    @ObservedObject var model: AppModel
    let grants: [FolderGrant]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Destination access").font(.headline)
            Text("Folders Mochi may move files into. They appear above under each watched folder that uses them.")
                .font(.caption).foregroundStyle(.secondary)
            ForEach(Array(grants.enumerated()), id: \.element.id) { index, grant in
                HStack(spacing: 12) {
                    Image(systemName: "folder.fill").foregroundStyle(.secondary)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(grant.displayName)
                        Text(grant.lastResolvedPathHint.map(abbreviated) ?? "Permission unavailable")
                            .font(.caption).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                    }
                    Spacer()
                    let count = model.rules.filter { rule in
                        if case .move(let destination) = rule.action.disposition { return destination.grantID == grant.id }
                        return false
                    }.count
                    Text(count == 0 ? "Not used yet" : "\(count) rule\(count == 1 ? "" : "s")")
                        .font(.caption).foregroundStyle(.secondary)
                    Button(role: .destructive) { Task { await model.removeFolder(grant) } } label: { Image(systemName: "trash") }
                        .buttonStyle(.borderless)
                        .accessibilityLabel("Remove \(grant.displayName)")
                        .accessibilityIdentifier("folder.remove.\(grant.id.uuidString)")
                        .help(count == 0 ? "Remove authorization" : "Remove authorization and the rules that use it")
                }
                .padding(.vertical, 5)
                if index < grants.count - 1 { Divider() }
            }
        }
        .padding(16)
        .cardStyle()
    }
}

private func abbreviated(_ path: String) -> String {
    let home = FileManager.default.homeDirectoryForCurrentUser.path
    return path.hasPrefix(home) ? "~" + path.dropFirst(home.count) : path
}

private struct RulesView: View {
    @ObservedObject var model: AppModel
    let createRule: () -> Void
    let editRule: (OrganizationRule) -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            PageHeader(title: "Rules", subtitle: "Rules run locally in priority order. Use the arrows to change precedence.") {
                HStack {
                    Button { model.selectedSection = .quickRules } label: { Label("Quick Rules", systemImage: AppSection.quickRules.icon) }
                    Button(action: createRule) { Label("New Rule", systemImage: "plus") }
                }
            }
            if model.rules.isEmpty {
                EmptyState(icon: "list.bullet.rectangle", title: "No rules yet", detail: "Create a rule to decide which files go where, or start with a Quick Rule.", buttonTitle: "Browse Quick Rules") {
                    model.selectedSection = .quickRules
                }
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                    ForEach(Array(model.rules.enumerated()), id: \.element.id) { index, rule in
                        HStack(spacing: 12) {
                            VStack(spacing: 2) {
                                Button { moveRule(at: index, up: true) } label: { Image(systemName: "chevron.up") }
                                    .buttonStyle(.borderless)
                                    .disabled(index == 0)
                                    .accessibilityLabel("Move \(rule.name) up")
                                Button { moveRule(at: index, up: false) } label: { Image(systemName: "chevron.down") }
                                    .buttonStyle(.borderless)
                                    .disabled(index == model.rules.count - 1)
                                    .accessibilityLabel("Move \(rule.name) down")
                            }
                            VStack(alignment: .leading, spacing: 3) {
                                Text(rule.name).font(.headline)
                                Text(ruleSummary(rule, grants: model.grants)).font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Toggle("Enabled", isOn: Binding(get: { rule.isEnabled }, set: { model.setRuleEnabled($0, id: rule.id) }))
                                .toggleStyle(.switch)
                                .controlSize(.small)
                                .labelsHidden()
                                .help(rule.isEnabled ? "Disable rule" : "Enable rule")
                            Button("Edit") { editRule(rule) }
                                .buttonStyle(.borderless)
                                .accessibilityIdentifier("rule.edit.\(rule.id.uuidString)")
                            Button(role: .destructive) { model.deleteRule(id: rule.id) } label: { Image(systemName: "trash") }
                                .buttonStyle(.borderless)
                                .accessibilityLabel("Delete \(rule.name)")
                                .accessibilityIdentifier("rule.delete.\(rule.id.uuidString)")
                        }
                        .padding(.vertical, 10)
                        .accessibilityElement(children: .contain)
                        if index < model.rules.count - 1 { Divider() }
                    }
                    }
                    .padding(.horizontal, 12)
                    .cardStyle()
                }
            }
        }.padding(28)
    }

    private func moveRule(at index: Int, up: Bool) {
        if up {
            guard index > 0 else { return }
            model.moveRules(from: IndexSet(integer: index), to: index - 1)
        } else {
            guard index < model.rules.count - 1 else { return }
            model.moveRules(from: IndexSet(integer: index), to: index + 2)
        }
    }
}

private struct ReviewView: View {
    @ObservedObject var model: AppModel
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            PageHeader(title: "Review", subtitle: "Nothing moves until you approve it.") {
                if !model.proposals.isEmpty {
                    Button("Approve All") { Task { await model.approveAll() } }.buttonStyle(.borderedProminent)
                }
            }
            if model.proposals.isEmpty {
                EmptyState(icon: "checkmark.circle", title: "All caught up", detail: "Run Organize Now to preview matching files.", buttonTitle: "Organize Now") {
                    Task { await model.runNow() }
                }
            } else {
                ScrollView {
                    LazyVStack(spacing: 12) {
                        ForEach(model.proposals) { proposal in
                            ProposalCard(proposal: proposal, ruleName: model.rules.first(where: { $0.id == proposal.ruleID })?.name) {
                                model.reject(proposal)
                            } approve: {
                                Task { await model.approve(proposal) }
                            }
                        }
                    }
                    .padding(.bottom, 4)
                }
            }
        }.padding(28)
    }
}

private struct ProposalCard: View {
    let proposal: ProposedOperation
    let ruleName: String?
    let skip: () -> Void
    let approve: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                Image(nsImage: NSWorkspace.shared.icon(forFile: proposal.source.url.path))
                    .resizable()
                    .frame(width: 34, height: 34)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(proposal.source.filename).font(.headline).lineLimit(1).truncationMode(.middle)
                    if let ruleName {
                        Label("Rule: \(ruleName)", systemImage: "list.bullet.rectangle")
                            .font(.caption).foregroundStyle(.secondary)
                    } else if proposal.aiExplanation != nil {
                        Label("AI suggestion", systemImage: "sparkles")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                Spacer()
                Button("Skip", action: skip)
                    .accessibilityIdentifier("proposal.skip.\(proposal.id.uuidString)")
                Button("Approve", action: approve)
                    .buttonStyle(.borderedProminent)
                    .accessibilityIdentifier("proposal.approve.\(proposal.id.uuidString)")
            }

            MoveRoute(from: proposal.source.url.deletingLastPathComponent(), to: proposal.destinationURL?.deletingLastPathComponent())

            if let explanation = proposal.aiExplanation, !explanation.isEmpty {
                Text(explanation)
                    .font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let destination = proposal.destinationURL, destination.lastPathComponent != proposal.source.filename {
                Label("Will be saved as “\(destination.lastPathComponent)”", systemImage: "pencil")
                    .font(.caption).foregroundStyle(.secondary)
            }
            if !proposal.warnings.isEmpty {
                Label(proposal.warnings.map(\.rawValue).joined(separator: ", "), systemImage: "exclamationmark.triangle.fill")
                    .font(.caption).foregroundStyle(.orange)
            }
        }
        .padding(16)
        .cardStyle()
        .accessibilityElement(children: .contain)
    }
}

struct MoveRoute: View {
    let from: URL
    let to: URL?
    var compact = false

    var body: some View {
        HStack(spacing: compact ? 6 : 10) {
            FolderChip(url: from, role: .source, compact: compact)
            Image(systemName: "arrow.right")
                .font(compact ? .caption.weight(.semibold) : .title3.weight(.semibold))
                .foregroundStyle(Color.accentColor)
                .accessibilityLabel("moves to")
            if let to {
                FolderChip(url: to, role: .destination, compact: compact)
            } else {
                Label("Destination unavailable", systemImage: "exclamationmark.triangle")
                    .font(compact ? .caption : .callout).foregroundStyle(.orange)
            }
        }
    }
}

struct FolderChip: View {
    enum Role { case source, destination }
    let url: URL
    let role: Role
    var compact = false

    var body: some View {
        if compact {
            Label(url.lastPathComponent, systemImage: role == .source ? "folder" : "folder.fill")
                .font(.caption.weight(role == .destination ? .semibold : .regular))
                .foregroundStyle(role == .destination ? Color.accentColor : Color.secondary)
                .lineLimit(1)
                .help(url.path)
        } else {
            HStack(spacing: 10) {
                Image(systemName: role == .source ? "folder" : "folder.fill")
                    .font(.title2)
                    .foregroundStyle(role == .destination ? Color.accentColor : Color.secondary)
                VStack(alignment: .leading, spacing: 2) {
                    Text(role == .source ? "FROM" : "TO")
                        .font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
                    Text(url.lastPathComponent).font(.body.weight(.semibold)).lineLimit(1)
                    Text(abbreviatedParent).font(.caption).foregroundStyle(.secondary).lineLimit(1).truncationMode(.head)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 9).fill(role == .destination ? Color.accentColor.opacity(0.12) : Color.secondary.opacity(0.08)))
            .overlay(RoundedRectangle(cornerRadius: 9).stroke(role == .destination ? Color.accentColor.opacity(0.35) : Color.clear))
            .help(url.path)
        }
    }

    private var abbreviatedParent: String {
        let parent = url.deletingLastPathComponent().path
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return parent.hasPrefix(home) ? "~" + parent.dropFirst(home.count) : parent
    }
}

private struct HistoryView: View {
    @ObservedObject var model: AppModel
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            PageHeader(title: "History", subtitle: "Every filesystem operation is journaled and eligible moves can be undone.") {
                Button { Task { await model.refresh() } } label: { Label("Refresh", systemImage: "arrow.clockwise") }
            }
            if model.history.isEmpty {
                EmptyState(icon: "clock.arrow.circlepath", title: "No activity yet", detail: "Approved operations will appear here.")
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                    ForEach(Array(model.history.enumerated()), id: \.element.id) { index, record in
                    HStack(spacing: 12) {
                        Image(systemName: record.state == .committed ? "checkmark.circle.fill" : "clock")
                            .foregroundStyle(record.state == .committed ? Color.green : Color.secondary)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(record.sourceURL.lastPathComponent).font(.headline)
                            Text("\(record.state.rawValue.capitalized) • \(record.createdAt.formatted(date: .abbreviated, time: .shortened))")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        if record.state == .committed {
                            Button("Undo") { Task { await model.undo(record) } }
                                .buttonStyle(.borderless)
                                .accessibilityIdentifier("history.undo.\(record.id.uuidString)")
                        }
                    }
                    .padding(.vertical, 10)
                    .accessibilityElement(children: .contain)
                        if index < model.history.count - 1 { Divider() }
                    }
                    }
                    .padding(.horizontal, 12)
                    .cardStyle()
                }
            }
        }.padding(28)
    }
}

struct SettingsView: View {
    @ObservedObject var model: AppModel
    @AppStorage("reviewAllAI") private var reviewAllAI = true
    @AppStorage("allowTextSnippets") private var allowTextSnippets = false
    @AppStorage("allowProviderFailover") private var allowProviderFailover = false
    @AppStorage("monthlyCostWarning") private var monthlyCostWarning = 5.0
    @StateObject private var aiSettings = AISettingsModel()
    var embedded = false

    init(model: AppModel, embedded: Bool = false) {
        self.model = model
        self.embedded = embedded
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if embedded {
                PageHeader(title: "Settings", subtitle: "Monitoring, AI providers and privacy controls.") { EmptyView() }
                    .padding(.horizontal, 28)
                    .padding(.top, 24)
            }
            Form {
                Section {
                    Toggle("Monitor watched folders", isOn: $model.monitoringEnabled)
                } header: {
                    Text("General")
                } footer: {
                    Text("Mochi only scans folders you explicitly authorize.")
                }

                Section {
                    LabeledContent("TypeSafe Jev API key") {
                        credentialField(saved: aiSettings.hasJevKey, text: $aiSettings.jevKeyEntry, remove: { aiSettings.removeJevKey() })
                    }
                    Picker("Generative provider", selection: $aiSettings.provider) {
                        ForEach(GenerativeProviderChoice.allCases) { Text($0.title).tag($0) }
                    }
                    .onChange(of: aiSettings.provider) { _ in aiSettings.providerChanged() }
                    TextField("Model", text: $aiSettings.model)
                    if aiSettings.provider == .ollama {
                        TextField("Ollama endpoint", text: $aiSettings.ollamaEndpoint)
                    } else {
                        LabeledContent("\(aiSettings.provider.title) API key") {
                            credentialField(saved: aiSettings.hasProviderKey, text: $aiSettings.providerKeyEntry, remove: { aiSettings.removeProviderKey() })
                        }
                    }
                    HStack {
                        if let status = aiSettings.statusMessage {
                            Text(status).font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button("Save Configuration") { aiSettings.save() }
                            .buttonStyle(.borderedProminent)
                            .disabled(!aiSettings.configurationIsComplete)
                    }
                } header: {
                    Text("Bring Your Own Key")
                } footer: {
                    Text("Classification uses TypeSafe Jev first, then your generative provider for ambiguous results and natural-language rules.")
                }

                Section {
                    Toggle("Review every AI suggestion", isOn: $reviewAllAI)
                    Toggle("Allow bounded document snippets", isOn: $allowTextSnippets)
                    Toggle("Allow provider failover", isOn: $allowProviderFailover)
                    TextField("Monthly cost warning", value: $monthlyCostWarning, format: .currency(code: "USD"))
                } header: {
                    Text("Privacy & Review")
                } footer: {
                    Text("API keys are stored in the macOS Keychain. Paths and bookmarks are never sent to providers. AI classification stays review-only until a model passes Mochi’s benchmark safety gate.")
                }
            }
            .formStyle(.grouped)
        }
    }

    private func credentialField(saved: Bool, text: Binding<String>, remove: @escaping () -> Void) -> some View {
        HStack(spacing: 8) {
            SecureField("", text: text, prompt: Text(saved ? "Saved — enter to replace" : "Required"))
                .textFieldStyle(.roundedBorder)
                .frame(minWidth: 180)
            CredentialStatus(saved: saved)
            if saved { Button("Remove", role: .destructive, action: remove) }
        }
    }
}

private struct ProfileView: View {
    @ObservedObject var account: AccountModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                PageHeader(
                    title: "Profile",
                    subtitle: account.isSignedIn ? "Your Mochi account." : "Sign up in one step with your Google account."
                ) { EmptyView() }
                if account.isSignedIn { signedIn } else { signedOut }
                if let status = account.statusMessage {
                    Text(status).font(.caption).foregroundStyle(.secondary)
                }
            }
            .padding(28)
            .frame(maxWidth: 640, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var signedOut: some View {
        SettingsCard(title: "Create your Mochi account") {
            Text("Use Google to sign up or sign in. Mochi only receives your name, email address, and profile picture.")
                .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 12) {
                Button { Task { await account.signInWithGoogle() } } label: {
                    HStack(spacing: 8) {
                        Text("G")
                            .font(.system(size: 14, weight: .bold, design: .rounded))
                            .foregroundStyle(Color(red: 0.26, green: 0.52, blue: 0.96))
                            .frame(width: 20, height: 20)
                            .background(Circle().fill(.white))
                        Text("Continue with Google").fontWeight(.medium)
                    }
                    .padding(.horizontal, 4)
                }
                .controlSize(.large)
                .buttonStyle(.borderedProminent)
                .disabled(account.isWorking)
                .accessibilityIdentifier("profile.google")
                if account.isWorking { ProgressView().controlSize(.small) }
            }
            if account.pendingFilesSorted > 0 {
                Label("\(account.pendingFilesSorted.formatted()) \(account.pendingFilesSorted == 1 ? "file" : "files") sorted on this Mac. Sign in to keep your total.", systemImage: "tray.full")
                    .font(.callout)
            }
            Text("Your files are still organized entirely on this Mac. Signing in is optional.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    private var usageCard: some View {
        SettingsCard(title: "Your Mochi stats") {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(account.totalFilesSorted.formatted())
                    .font(.system(size: 40, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .accessibilityIdentifier("profile.filesSorted")
                Text(account.totalFilesSorted == 1 ? "file sorted with Mochi" : "files sorted with Mochi")
                    .foregroundStyle(.secondary)
                Spacer()
                Text(account.isPro ? "Pro plan" : "Free plan")
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 8).padding(.vertical, 4)
                    .background(Capsule().fill(Color.accentColor.opacity(0.15)))
                    .foregroundStyle(Color.accentColor)
            }
            Text(account.pendingFilesSorted > 0 && account.syncedFilesSorted != nil
                 ? "Syncing \(account.pendingFilesSorted.formatted()) recent \(account.pendingFilesSorted == 1 ? "move" : "moves")…"
                 : "Counted across every Mac where you're signed in. Only the number is synced, never file names or contents.")
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
    }

    private var signedIn: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 14) {
                AccountAvatar(account: account, size: 56)
                VStack(alignment: .leading, spacing: 3) {
                    Text(account.displayName).font(.title2.bold())
                    if let email = account.email { Text(email).foregroundStyle(.secondary) }
                    Label("Signed in with Google", systemImage: "checkmark.seal.fill")
                        .font(.caption).foregroundStyle(.green)
                }
            }

            usageCard

            SettingsCard(title: "Mochi Pro") {
                if account.isPro {
                    Label("Your subscription is active", systemImage: "checkmark.seal.fill")
                        .foregroundStyle(.green)
                    Text("\(account.proEntitlement.requestsUsed.formatted()) of \(account.proEntitlement.requestLimit.formatted()) hosted AI requests used this month.")
                        .font(.callout).foregroundStyle(.secondary)
                    HStack {
                        Button("Manage Subscription") { Task { await account.manageSubscription() } }
                        Button("Refresh Plan") { Task { await account.refreshPlan() } }
                    }
                } else {
                    Text("Hosted Jev + DeepSeek classification without managing your own API keys. AI suggestions still use Mochi’s local validation and review flow.")
                        .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    HStack {
                        Button("Upgrade to Mochi Pro") { Task { await account.upgradeToPro() } }
                            .buttonStyle(.borderedProminent)
                        Button("Refresh Plan") { Task { await account.refreshPlan() } }
                    }
                }
            }

            SettingsCard(title: "Display name") {
                HStack {
                    TextField("Your name", text: $account.displayNameEntry)
                        .textFieldStyle(.roundedBorder)
                        .onSubmit { Task { await account.saveDisplayName() } }
                    Button("Save") { Task { await account.saveDisplayName() } }
                        .buttonStyle(.borderedProminent)
                        .disabled(!account.displayNameChanged || account.isWorking)
                }
            }

            Button("Sign Out", role: .destructive) { Task { await account.signOut() } }
                .disabled(account.isWorking)
                .accessibilityIdentifier("profile.signOut")
        }
    }
}

private struct AccountAvatar: View {
    @ObservedObject var account: AccountModel
    let size: CGFloat

    var body: some View {
        Group {
            if let url = account.avatarURL {
                AsyncImage(url: url) { image in
                    image.resizable().scaledToFill()
                } placeholder: { placeholder }
            } else {
                placeholder
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .accessibilityHidden(true)
    }

    private var placeholder: some View {
        ZStack {
            Circle().fill(Color.accentColor.opacity(account.isSignedIn ? 0.85 : 0.18))
            if account.isSignedIn {
                Text(account.initials).font(.system(size: size * 0.4, weight: .semibold)).foregroundStyle(.white)
            } else {
                Image(systemName: "person.fill").font(.system(size: size * 0.45)).foregroundStyle(Color.accentColor)
            }
        }
    }
}

private struct SettingsCard<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title).font(.headline)
            content
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardStyle()
    }
}

private struct CredentialStatus: View {
    let saved: Bool
    var body: some View {
        Label(saved ? "Saved" : "Missing", systemImage: saved ? "checkmark.circle.fill" : "exclamationmark.circle")
            .font(.caption)
            .foregroundStyle(saved ? Color.green : Color.secondary)
            .frame(width: 76, alignment: .leading)
    }
}

private struct RuleEditorView: View {
    let existing: OrganizationRule?
    let sourceGrants: [FolderGrant]
    let destinationGrants: [FolderGrant]
    let onSave: (OrganizationRule) -> Void
    let onCancel: () -> Void

    @State private var name: String
    @State private var extensions: String
    @State private var filenameContains: String
    @State private var sourceID: UUID?
    @State private var destinationID: UUID?
    @State private var subfolder: String
    @State private var renameTemplate: String
    @State private var enabled: Bool
    @State private var leaveUntouched: Bool

    init(existing: OrganizationRule?, sourceGrants: [FolderGrant], destinationGrants: [FolderGrant], onSave: @escaping (OrganizationRule) -> Void, onCancel: @escaping () -> Void) {
        self.existing = existing
        self.sourceGrants = sourceGrants
        self.destinationGrants = destinationGrants
        self.onSave = onSave
        self.onCancel = onCancel
        let values = existing?.match.predicates.reduce(into: (extensions: [String](), filename: "")) { result, predicate in
            switch predicate {
            case .fileExtension(let extensions): result.extensions = extensions
            case .filename(.contains, let value): result.filename = value
            default: break
            }
        }
        let destination: DestinationReference? = {
            guard let existing, case .move(let value) = existing.action.disposition else { return nil }
            return value
        }()
        _name = State(initialValue: existing?.name ?? "")
        _extensions = State(initialValue: values?.extensions.joined(separator: ", ") ?? "")
        _filenameContains = State(initialValue: values?.filename ?? "")
        _sourceID = State(initialValue: existing?.sourceGrantIDs.first ?? sourceGrants.first?.id)
        _destinationID = State(initialValue: destination?.grantID ?? destinationGrants.first?.id)
        _subfolder = State(initialValue: destination?.relativeSubpath ?? "")
        _renameTemplate = State(initialValue: existing?.action.renameTemplate ?? "")
        _enabled = State(initialValue: existing?.isEnabled ?? true)
        if let existing, case .leave = existing.action.disposition { _leaveUntouched = State(initialValue: true) }
        else { _leaveUntouched = State(initialValue: false) }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack { Text(existing == nil ? "New Rule" : "Edit Rule").font(.title2.bold()); Spacer() }.padding(20)
            Divider()
            Form {
                TextField("Rule name", text: $name)
                Picker("Watch folder", selection: $sourceID) {
                    Text("All watched folders").tag(UUID?.none)
                    ForEach(sourceGrants) { Text($0.displayName).tag(Optional($0.id)) }
                }
                TextField("File extensions", text: $extensions, prompt: Text("pdf, png, zip"))
                TextField("Filename contains", text: $filenameContains, prompt: Text("Optional"))
                Toggle("Leave matching files untouched", isOn: $leaveUntouched)
                if !leaveUntouched {
                    Picker("Destination", selection: $destinationID) {
                        Text("Choose a destination").tag(UUID?.none)
                        ForEach(destinationGrants) { Text($0.displayName).tag(Optional($0.id)) }
                    }
                    TextField("Subfolder", text: $subfolder, prompt: Text("Optional"))
                    TextField("Rename template", text: $renameTemplate, prompt: Text("Optional: {name}-{created:yyyy-MM-dd}.{ext}"))
                }
                Toggle("Enable this rule", isOn: $enabled)
            }.formStyle(.grouped)
            Divider()
            HStack {
                Button("Cancel", action: onCancel).keyboardShortcut(.cancelAction)
                Spacer()
                Button("Save Rule", action: save).buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction).disabled(!canSave)
            }.padding(16)
        }.frame(width: 560, height: 520)
    }

    private var canSave: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        (!extensions.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !filenameContains.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) &&
        (leaveUntouched || destinationID != nil)
    }

    private func save() {
        var predicates: [RulePredicate] = []
        let values = extensions.split(separator: ",").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        if !values.isEmpty { predicates.append(.fileExtension(values: values)) }
        let filename = filenameContains.trimmingCharacters(in: .whitespacesAndNewlines)
        if !filename.isEmpty { predicates.append(.filename(operation: .contains, value: filename)) }
        let action: RuleAction
        if leaveUntouched { action = .init(disposition: .leave) }
        else if let destinationID {
            action = .init(
                disposition: .move(.init(grantID: destinationID, relativeSubpath: subfolder.trimmingCharacters(in: .whitespacesAndNewlines))),
                renameTemplate: renameTemplate.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : renameTemplate
            )
        } else { return }
        onSave(.init(
            id: existing?.id ?? UUID(), name: name.trimmingCharacters(in: .whitespacesAndNewlines), isEnabled: enabled,
            priority: existing?.priority ?? 0, sourceGrantIDs: sourceID.map { [$0] } ?? [],
            match: .init(operation: .all, predicates: predicates), action: action, origin: existing?.origin ?? .user
        ))
    }
}

private struct PageHeader<Actions: View>: View {
    let title: String
    let subtitle: String
    @ViewBuilder let actions: Actions
    var body: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) { Text(title).font(.largeTitle.bold()); Text(subtitle).foregroundStyle(.secondary) }
            Spacer(); actions
        }
    }
}

private struct EmptyState: View {
    let icon: String
    let title: String
    let detail: String
    var buttonTitle: String?
    var action: (() -> Void)?
    var body: some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: icon).font(.system(size: 42)).foregroundStyle(.secondary)
            Text(title).font(.title2.bold())
            Text(detail).foregroundStyle(.secondary).multilineTextAlignment(.center)
            if let buttonTitle, let action { Button(buttonTitle, action: action).buttonStyle(.borderedProminent) }
            Spacer()
        }.frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private func ruleSummary(_ rule: OrganizationRule, grants: [FolderGrant]) -> String {
    let conditions = rule.match.predicates.map { predicate -> String in
        switch predicate {
        case .fileExtension(let values): "extension is \(values.joined(separator: ", "))"
        case .filename(let operation, let value): "filename \(operation.rawValue) \(value)"
        case .contentType(let value): "type is \(value)"
        case .size(let comparison, let bytes): "size \(comparison.rawValue) \(bytes) bytes"
        case .creationDate: "creation date matches"
        case .modificationDate: "modified date matches"
        case .finderTag(let values, _): "tags include \(values.joined(separator: ", "))"
        case .isHidden(let value): value ? "is hidden" : "is visible"
        }
    }.joined(separator: " and ")
    let action: String
    switch rule.action.disposition {
    case .leave: action = "leave untouched"
    case .move(let destination):
        let name = grants.first(where: { $0.id == destination.grantID })?.displayName ?? "Unavailable destination"
        action = "move to \(name)\(destination.relativeSubpath.isEmpty ? "" : "/\(destination.relativeSubpath)")"
    }
    return "If \(conditions), \(action)."
}

private struct CardStyle: ViewModifier {
    var highlighted = false

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: 12, style: .continuous)
        content
            .background(shape.fill(Color(nsColor: .controlBackgroundColor)))
            .overlay(shape.strokeBorder(highlighted ? Color.accentColor.opacity(0.55) : Color(nsColor: .separatorColor), lineWidth: 1))
    }
}

private extension View {
    func cardStyle(highlighted: Bool = false) -> some View { modifier(CardStyle(highlighted: highlighted)) }
}

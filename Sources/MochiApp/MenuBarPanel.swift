import AppKit
import MochiCore
import SwiftUI

@MainActor
enum MochiMenuBarIcon {
    static let image: NSImage = {
        let image = NSImage(size: NSSize(width: 20, height: 18), flipped: false) { _ in
            guard let context = NSGraphicsContext.current else { return false }
            NSColor.black.setFill()
            NSColor.black.setStroke()

            NSBezierPath(ovalIn: NSRect(x: 4.75, y: 7, width: 11, height: 11)).fill()

            context.compositingOperation = .clear
            NSBezierPath(ovalIn: NSRect(x: 7.4, y: 13, width: 1.6, height: 1.9)).fill()
            NSBezierPath(ovalIn: NSRect(x: 11.5, y: 13, width: 1.6, height: 1.9)).fill()
            let smile = NSBezierPath()
            smile.appendArc(withCenter: NSPoint(x: 10.25, y: 12.6), radius: 1.2, startAngle: 200, endAngle: 340)
            smile.lineWidth = 0.9
            smile.lineCapStyle = .round
            smile.stroke()

            let folder = NSBezierPath()
            folder.move(to: NSPoint(x: 4, y: 0.75))
            folder.appendArc(from: NSPoint(x: 19.5, y: 0.75), to: NSPoint(x: 19.5, y: 9.75), radius: 2.2)
            folder.appendArc(from: NSPoint(x: 19.5, y: 9.75), to: NSPoint(x: 7.5, y: 9.75), radius: 2)
            folder.appendArc(from: NSPoint(x: 7.5, y: 9.75), to: NSPoint(x: 6, y: 11.75), radius: 0.8)
            folder.appendArc(from: NSPoint(x: 6, y: 11.75), to: NSPoint(x: 1, y: 11.75), radius: 0.8)
            folder.appendArc(from: NSPoint(x: 1, y: 11.75), to: NSPoint(x: 1, y: 0.75), radius: 1.6)
            folder.appendArc(from: NSPoint(x: 1, y: 0.75), to: NSPoint(x: 19.5, y: 0.75), radius: 2.2)
            folder.close()
            folder.lineWidth = 2
            folder.stroke()

            context.compositingOperation = .sourceOver
            folder.fill()
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = "Mochi"
        return image
    }()
}

struct MenuBarPanel: View {
    @ObservedObject var model: AppModel
    let openDashboard: (AppSection) -> Void
    @State private var lastAction: LastAction?
    @State private var dismissTask: Task<Void, Never>?

    private static let visibleCount = 3

    private struct LastAction: Identifiable {
        let id = UUID()
        let message: String
        let isError: Bool
        let undo: (@MainActor () async -> Void)?
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header.padding(14)
            Divider()
            content.padding(14)
            if let lastAction {
                actionBar(lastAction).transition(.move(edge: .bottom).combined(with: .opacity))
            }
            Divider()
            footer.padding(.horizontal, 10).padding(.vertical, 8)
        }
        .frame(width: 360)
        .animation(.easeInOut(duration: 0.2), value: model.proposals.map(\.id))
        .animation(.easeInOut(duration: 0.2), value: lastAction?.id)
    }

    private var header: some View {
        HStack(spacing: 10) {
            Image(nsImage: NSApplication.shared.applicationIconImage)
                .resizable()
                .frame(width: 30, height: 30)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 1) {
                Text("Mochi").font(.headline)
                Text(statusText).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Toggle("Monitoring", isOn: $model.monitoringEnabled)
                .toggleStyle(.switch)
                .controlSize(.small)
                .labelsHidden()
                .help(model.monitoringEnabled ? "Pause monitoring" : "Resume monitoring")
        }
    }

    private var statusText: String {
        guard model.monitoringEnabled else { return "Monitoring paused" }
        let count = model.sourceGrants.filter(\.isMonitoringEnabled).count
        return count == 0 ? "No folders watched" : "Watching \(count) folder\(count == 1 ? "" : "s")"
    }

    private var needsSetup: Bool {
        model.sourceGrants.isEmpty || model.destinationGrants.isEmpty || !model.rules.contains(where: \.isEnabled)
    }

    @ViewBuilder private var content: some View {
        if model.proposals.isEmpty {
            emptyState
        } else {
            reviewQueue
        }
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(nsImage: MochiMenuBarIcon.image)
                .resizable()
                .renderingMode(.template)
                .frame(width: 40, height: 36)
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            if needsSetup {
                Text("Finish setting up Mochi").font(.headline)
                Text("Add a watched folder, a destination and a rule to start sorting.")
                    .font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center)
                Button("Open Setup") { open(.overview) }.buttonStyle(.borderedProminent)
            } else {
                Text("All tidy").font(.headline)
                Text("No files are waiting for review.").font(.caption).foregroundStyle(.secondary)
                HStack(spacing: 8) {
                    Button("Organize Now") { Task { await organize() } }
                        .buttonStyle(.borderedProminent)
                        .disabled(model.isBusy)
                    if model.isBusy { ProgressView().controlSize(.small) }
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
    }

    private var reviewQueue: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("\(model.proposals.count) \(model.proposals.count == 1 ? "file" : "files") to review").font(.headline)
                Spacer()
                Button("Approve All") { Task { await approveAll() } }
                    .controlSize(.small)
                    .disabled(model.isBusy)
            }
            VStack(spacing: 6) {
                ForEach(Array(model.proposals.prefix(Self.visibleCount).enumerated()), id: \.element.id) { index, proposal in
                    MenuBarProposalRow(proposal: proposal, isFocused: index == 0) {
                        skip(proposal)
                    } approve: {
                        Task { await approve(proposal) }
                    }
                    .transition(.asymmetric(insertion: .opacity, removal: .move(edge: .trailing).combined(with: .opacity)))
                }
            }
            HStack {
                Text("Return approves · Delete skips the top file")
                    .font(.caption2).foregroundStyle(.tertiary)
                Spacer()
                if model.proposals.count > Self.visibleCount {
                    Button("\(model.proposals.count - Self.visibleCount) more…") { open(.review) }
                        .buttonStyle(.link)
                        .font(.caption)
                }
            }
        }
    }

    private func actionBar(_ action: LastAction) -> some View {
        HStack(spacing: 8) {
            Image(systemName: action.isError ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                .foregroundStyle(action.isError ? Color.orange : Color.green)
            Text(action.message).font(.caption).lineLimit(2)
            Spacer()
            if let undo = action.undo {
                Button("Undo") {
                    lastAction = nil
                    Task { await undo() }
                }
                .controlSize(.small)
                .keyboardShortcut("z", modifiers: .command)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .background(Color.secondary.opacity(0.08))
    }

    private var footer: some View {
        HStack(spacing: 4) {
            Button { open(.overview) } label: { Label("Open Mochi", systemImage: "macwindow") }
            Spacer()
            Button { open(.profile) } label: { Image(systemName: "person.crop.circle") }.help("Profile")
            Button { open(.settings) } label: { Image(systemName: "gearshape") }.help("Settings")
            Button { NSApplication.shared.terminate(nil) } label: { Image(systemName: "power") }.help("Quit Mochi")
        }
        .buttonStyle(.borderless)
    }

    private func approve(_ proposal: ProposedOperation) async {
        guard let record = await model.approve(proposal) else {
            show(LastAction(message: model.notice ?? "Could not move \(proposal.source.filename).", isError: true, undo: nil))
            return
        }
        let folder = record.destinationURL?.deletingLastPathComponent().lastPathComponent ?? "its folder"
        show(LastAction(message: "Moved \(proposal.source.filename) to \(folder)", isError: false) {
            await model.undo(record)
            model.restore(proposal)
        })
    }

    private func approveAll() async {
        var moved: [(ProposedOperation, OperationRecord)] = []
        for proposal in model.proposals {
            if let record = await model.approve(proposal) { moved.append((proposal, record)) }
        }
        guard !moved.isEmpty else { return }
        show(LastAction(message: "Moved \(moved.count) file\(moved.count == 1 ? "" : "s")", isError: false) {
            for (proposal, record) in moved.reversed() {
                await model.undo(record)
                model.restore(proposal)
            }
        })
    }

    private func skip(_ proposal: ProposedOperation) {
        model.reject(proposal)
        show(LastAction(message: "Skipped \(proposal.source.filename)", isError: false) {
            model.restore(proposal)
        })
    }

    private func organize() async {
        await model.runNow(openReview: false)
        if model.proposals.isEmpty {
            show(LastAction(message: model.notice ?? "No files matched your rules.", isError: false, undo: nil))
        }
    }

    private func show(_ action: LastAction) {
        lastAction = action
        dismissTask?.cancel()
        dismissTask = Task {
            try? await Task.sleep(nanoseconds: 6_000_000_000)
            guard !Task.isCancelled else { return }
            if lastAction?.id == action.id { lastAction = nil }
        }
    }

    private func open(_ section: AppSection) {
        NSApplication.shared.windows
            .first { $0.className.contains("MenuBarExtra") }?
            .orderOut(nil)
        openDashboard(section)
    }
}

private struct MenuBarProposalRow: View {
    let proposal: ProposedOperation
    let isFocused: Bool
    let skip: () -> Void
    let approve: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(nsImage: NSWorkspace.shared.icon(forFile: proposal.source.url.path))
                .resizable()
                .frame(width: 30, height: 30)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text(proposal.source.filename)
                    .font(.callout.weight(.medium))
                    .lineLimit(1)
                    .truncationMode(.middle)
                MoveRoute(from: proposal.source.url.deletingLastPathComponent(), to: proposal.destinationURL?.deletingLastPathComponent(), compact: true)
            }
            .help(proposal.destinationURL.map { "\(proposal.source.url.path) → \($0.path)" } ?? proposal.source.url.path)
            Spacer(minLength: 4)
            Button(action: skip) {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.secondary)
                    .frame(width: 26, height: 26)
                    .background(Circle().fill(Color.secondary.opacity(0.15)))
            }
            .buttonStyle(.plain)
            .help("Skip")
            .accessibilityLabel("Skip \(proposal.source.filename)")
            .keyboardShortcut(isFocused ? KeyboardShortcut(.delete, modifiers: []) : nil)
            Button(action: approve) {
                Image(systemName: "checkmark")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 26, height: 26)
                    .background(Circle().fill(Color.accentColor))
            }
            .buttonStyle(.plain)
            .help("Approve move")
            .accessibilityLabel("Approve \(proposal.source.filename)")
            .keyboardShortcut(isFocused ? .defaultAction : nil)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(RoundedRectangle(cornerRadius: 9).fill(isFocused ? Color.accentColor.opacity(0.1) : Color.secondary.opacity(0.06)))
        .overlay(RoundedRectangle(cornerRadius: 9).stroke(isFocused ? Color.accentColor.opacity(0.3) : Color.clear))
    }
}

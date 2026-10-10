import AppKit
import SwiftUI

@MainActor
private enum MochiRuntime {
    static let account = AccountModel()
    static let model: AppModel = {
        let model = AppModel()
        model.onFilesSorted = { account.recordSortedFiles($0) }
        return model
    }()
}

@MainActor
final class MochiAppDelegate: NSObject, NSApplicationDelegate {
    private var dashboard: DashboardWindowController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApplication.shared.setActivationPolicy(.regular)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
            self?.showDashboard(section: .overview)
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showDashboard(section: MochiRuntime.model.selectedSection ?? .overview)
        return true
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    func showDashboard(section: AppSection) {
        MochiRuntime.model.selectedSection = section
        let controller = dashboard ?? DashboardWindowController(model: MochiRuntime.model, account: MochiRuntime.account)
        dashboard = controller
        controller.window?.makeKeyAndOrderFront(nil)
        NSApplication.shared.activate(ignoringOtherApps: true)
    }
}

@main
struct MochiApplication: App {
    @NSApplicationDelegateAdaptor(MochiAppDelegate.self) private var appDelegate
    @StateObject private var model = MochiRuntime.model

    var body: some Scene {
        MenuBarExtra {
            MenuBarPanel(model: model) { section in
                appDelegate.showDashboard(section: section)
            }
        } label: {
            Image(nsImage: MochiMenuBarIcon.image)
            if !model.proposals.isEmpty {
                Text("\(model.proposals.count)")
            }
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView(model: model)
                .frame(minWidth: 680, idealWidth: 720, minHeight: 520, idealHeight: 620)
        }
    }
}
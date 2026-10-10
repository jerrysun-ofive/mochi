import AppKit
import Combine
import SwiftUI

@MainActor
final class DashboardWindowController: NSWindowController, NSToolbarDelegate, NSToolbarItemValidation {
    private static let organizeItem = NSToolbarItem.Identifier("app.mochi.toolbar.organize")
    private static let newRuleItem = NSToolbarItem.Identifier("app.mochi.toolbar.newRule")

    private let model: AppModel
    private var busyObserver: AnyCancellable?

    init(model: AppModel, account: AccountModel) {
        self.model = model
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 940, height: 640),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = "Mochi"
        window.titleVisibility = .hidden
        window.minSize = NSSize(width: 820, height: 560)
        window.isReleasedWhenClosed = false
        let hosting = NSHostingController(rootView: DashboardView(model: model, account: account))
        if #available(macOS 14, *) { hosting.sceneBridgingOptions = [] }
        window.contentViewController = hosting
        window.setContentSize(NSSize(width: 940, height: 640))
        super.init(window: window)

        let toolbar = NSToolbar(identifier: "app.mochi.dashboard")
        toolbar.delegate = self
        toolbar.displayMode = .iconOnly
        toolbar.allowsUserCustomization = false
        window.toolbar = toolbar
        window.toolbarStyle = .unified
        window.center()

        busyObserver = model.$isBusy.receive(on: RunLoop.main).sink { [weak toolbar] _ in
            toolbar?.validateVisibleItems()
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        [.toggleSidebar, .sidebarTrackingSeparator, .flexibleSpace, Self.organizeItem, Self.newRuleItem]
    }

    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        toolbarDefaultItemIdentifiers(toolbar)
    }

    func toolbar(_ toolbar: NSToolbar, itemForItemIdentifier identifier: NSToolbarItem.Identifier, willBeInsertedIntoToolbar flag: Bool) -> NSToolbarItem? {
        switch identifier {
        case Self.organizeItem:
            let item = button(identifier, title: "Organize Now", symbol: "sparkles", help: "Find files that match your rules", action: #selector(organizeNow))
            item.title = "Organize Now"
            return item
        case Self.newRuleItem:
            return button(identifier, title: "New Rule", symbol: "plus", help: "Create a new rule", action: #selector(newRule))
        default:
            return nil
        }
    }

    func validateToolbarItem(_ item: NSToolbarItem) -> Bool {
        item.itemIdentifier == Self.organizeItem ? !model.isBusy : true
    }

    private func button(_ identifier: NSToolbarItem.Identifier, title: String, symbol: String, help: String, action: Selector) -> NSToolbarItem {
        let item = NSToolbarItem(itemIdentifier: identifier)
        item.label = title
        item.paletteLabel = title
        item.toolTip = help
        item.image = NSImage(systemSymbolName: symbol, accessibilityDescription: title)
        item.isBordered = true
        item.target = self
        item.action = action
        return item
    }

    @objc private func organizeNow() {
        Task { await model.runNow() }
    }

    @objc private func newRule() {
        model.ruleEditor = RuleEditorPresentation(rule: nil)
    }
}

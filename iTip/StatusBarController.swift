import AppKit

final class StatusBarController: NSObject, NSMenuDelegate {
    static let defaultTitle = "iTip"

    let statusItem: NSStatusItem?

    private let applyTitle: (String) -> Void
    private let removeStatusItem: () -> Void
    private let menuPresenter: MenuPresenter?

    init(statusBar: NSStatusBar = .system, menuPresenter: MenuPresenter? = nil) {
        let statusItem = statusBar.statusItem(withLength: NSStatusItem.variableLength)

        self.statusItem = statusItem
        self.menuPresenter = menuPresenter
        applyTitle = { statusItem.button?.title = $0 }
        removeStatusItem = { statusBar.removeStatusItem(statusItem) }

        super.init()

        // Use SF Symbol for menu bar icon
        if let image = NSImage(systemSymbolName: "bolt.circle.fill", accessibilityDescription: "iTip") {
            image.isTemplate = true
            statusItem.button?.image = image
            statusItem.button?.title = ""
        } else {
            applyTitle(Self.defaultTitle)
        }

        if let menuPresenter = menuPresenter {
            let menu = menuPresenter.buildMenu()
            menu.delegate = self
            statusItem.menu = menu
        }
    }

    init(applyTitle: @escaping (String) -> Void, removeStatusItem: @escaping () -> Void = {}) {
        statusItem = nil
        self.menuPresenter = nil
        self.applyTitle = applyTitle
        self.removeStatusItem = removeStatusItem

        super.init()

        applyTitle(Self.defaultTitle)
    }

    deinit {
        removeStatusItem()
    }

    // MARK: - NSMenuDelegate

    func menuNeedsUpdate(_ menu: NSMenu) {
        guard let menuPresenter = menuPresenter else { return }
        // Build fresh menu and swap items in
        let freshMenu = menuPresenter.buildMenu()
        menu.removeAllItems()
        // Move items from fresh menu to existing menu
        while freshMenu.items.count > 0 {
            let item = freshMenu.items[0]
            freshMenu.removeItem(at: 0)
            menu.addItem(item)
        }
    }
}

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

        applyTitle(Self.defaultTitle)

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
        let freshMenu = menuPresenter.buildMenu()
        menu.removeAllItems()
        for item in freshMenu.items {
            freshMenu.removeItem(item)
            menu.addItem(item)
        }
        menu.delegate = self
    }
}

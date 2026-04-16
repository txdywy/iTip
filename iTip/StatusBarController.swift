import AppKit

final class StatusBarController {
    static let defaultTitle = "iTip"

    let statusItem: NSStatusItem?

    private let applyTitle: (String) -> Void
    private let removeStatusItem: () -> Void

    init(statusBar: NSStatusBar = .system) {
        let statusItem = statusBar.statusItem(withLength: NSStatusItem.variableLength)

        self.statusItem = statusItem
        applyTitle = { statusItem.button?.title = $0 }
        removeStatusItem = { statusBar.removeStatusItem(statusItem) }

        applyTitle(Self.defaultTitle)
    }

    init(applyTitle: @escaping (String) -> Void, removeStatusItem: @escaping () -> Void = {}) {
        statusItem = nil
        self.applyTitle = applyTitle
        self.removeStatusItem = removeStatusItem

        applyTitle(Self.defaultTitle)
    }

    deinit {
        removeStatusItem()
    }
}

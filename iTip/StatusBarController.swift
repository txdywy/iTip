import AppKit

final class StatusBarController {
    static let defaultTitle = "iTip"

    let statusItem: NSStatusItem

    init(statusBar: NSStatusBar = .system) {
        statusItem = statusBar.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.title = Self.defaultTitle
    }
}

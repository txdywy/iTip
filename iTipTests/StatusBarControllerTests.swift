import AppKit
@testable import iTip

func statusBarControllerSmokeTest() {
    let controller = StatusBarController(statusBar: NSStatusBar())
    precondition(controller.statusItem.button?.title == StatusBarController.defaultTitle)
}

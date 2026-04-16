import AppKit
import XCTest
@testable import iTip

final class StatusBarControllerTests: XCTestCase {
    func testStatusBarControllerSetsDefaultTitle() {
        let controller = StatusBarController(statusBar: NSStatusBar())

        XCTAssertEqual(controller.statusItem.button?.title, StatusBarController.defaultTitle)
    }
}

import XCTest
@testable import iTip

final class StatusBarControllerTests: XCTestCase {
    func testStatusBarControllerAssignsDefaultTitle() {
        let titleSpy = TitleSpy()

        _ = StatusBarController(applyTitle: titleSpy.record)

        XCTAssertEqual(titleSpy.recordedTitles, [StatusBarController.defaultTitle])
    }

    func testStatusBarControllerRemovesStatusItemOnDeinit() {
        let removalSpy = RemovalSpy()

        var controller: StatusBarController? = StatusBarController(
            applyTitle: { _ in },
            removeStatusItem: removalSpy.record
        )
        controller = nil

        XCTAssertEqual(removalSpy.removalCount, 1)
    }
}

private final class TitleSpy {
    private(set) var recordedTitles: [String] = []

    func record(_ title: String) {
        recordedTitles.append(title)
    }
}

private final class RemovalSpy {
    private(set) var removalCount = 0

    func record() {
        removalCount += 1
    }
}

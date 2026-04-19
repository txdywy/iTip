import XCTest
@testable import iTip

@MainActor
final class StatusBarControllerTests: XCTestCase {
    func testStatusBarControllerAssignsDefaultTitle() async {
        let titleSpy = TitleSpy()

        _ = StatusBarController(applyTitle: titleSpy.record)

        XCTAssertEqual(titleSpy.recordedTitles, [StatusBarController.defaultTitle])
    }

    func testStatusBarControllerRemovesStatusItemOnDeinit() async {
        let removalSpy = RemovalSpy()

        do {
            _ = StatusBarController(
                applyTitle: { _ in },
                removeStatusItem: removalSpy.record
            )
        }

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

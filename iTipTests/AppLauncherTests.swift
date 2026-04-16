import XCTest
@testable import iTip

final class AppLauncherTests: XCTestCase {
    private var launcher: AppLauncher!

    override func setUp() {
        super.setUp()
        launcher = AppLauncher()
    }

    func testActivateCallsBackWithApplicationNotFoundForUnknownBundleIdentifier() {
        let expectation = expectation(description: "completion called")
        let unknownID = "com.nonexistent.app.that.does.not.exist.12345"

        launcher.activate(bundleIdentifier: unknownID) { result in
            switch result {
            case .failure(let error):
                if case .applicationNotFound(let bundleId) = error {
                    XCTAssertEqual(bundleId, unknownID)
                } else {
                    XCTFail("Expected applicationNotFound error, got \(error)")
                }
            case .success:
                XCTFail("Expected failure for unknown bundle identifier, got success")
            }
            expectation.fulfill()
        }

        waitForExpectations(timeout: 5)
    }
}

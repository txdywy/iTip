import XCTest
@testable import iTip

final class AppLauncherTests: XCTestCase {
    private var launcher: AppLauncher!

    override func setUp() {
        super.setUp()
        launcher = AppLauncher()
    }

    func testActivateReturnsApplicationNotFoundForUnknownBundleIdentifier() {
        let result = launcher.activate(bundleIdentifier: "com.nonexistent.app.that.does.not.exist.12345")

        switch result {
        case .failure(let error):
            if case .applicationNotFound(let bundleId) = error {
                XCTAssertEqual(bundleId, "com.nonexistent.app.that.does.not.exist.12345")
            } else {
                XCTFail("Expected applicationNotFound error, got \(error)")
            }
        case .success:
            XCTFail("Expected failure for unknown bundle identifier, got success")
        }
    }
}

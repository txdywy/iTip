import XCTest
@testable import iTip

final class ProcessUtilsTests: XCTestCase {

    // MARK: - ProcessRunner timeout test

    /// Verify that ProcessRunner.run() terminates a long-running process
    /// within the specified timeout and returns nil.
    func testRunWithTimeoutTerminatesSlowProcess() {
        let startTime = Date()

        // Run /bin/sleep 10 with a 1-second timeout
        let result = ProcessRunner.run(
            executableURL: URL(fileURLWithPath: "/bin/sleep"),
            arguments: ["10"],
            timeout: 1.0
        )

        let elapsed = Date().timeIntervalSince(startTime)

        // Should return nil because the process was terminated (non-zero exit)
        XCTAssertNil(result, "Timed-out process should return nil")

        // Should complete well under 3 seconds (proving timeout worked, not 10s sleep)
        XCTAssertLessThan(elapsed, 3.0,
                          "Process should be terminated by timeout, not run for full 10 seconds")
    }

    // MARK: - ProcessRunner successful execution

    /// Verify that a quick command completes successfully and returns output.
    func testRunSuccessfulCommand() {
        let result = ProcessRunner.run(
            executableURL: URL(fileURLWithPath: "/bin/echo"),
            arguments: ["hello"]
        )

        XCTAssertNotNil(result)
        XCTAssertEqual(result?.trimmingCharacters(in: .whitespacesAndNewlines), "hello")
    }

    // MARK: - ProcessRunner with non-existent executable

    /// Verify that running a non-existent executable returns nil gracefully.
    func testRunNonExistentExecutableReturnsNil() {
        let result = ProcessRunner.run(
            executableURL: URL(fileURLWithPath: "/nonexistent/binary"),
            arguments: []
        )

        XCTAssertNil(result, "Non-existent executable should return nil")
    }

    // MARK: - ProcessRunner with failing command

    /// Verify that a command exiting with non-zero status returns nil.
    func testRunFailingCommandReturnsNil() {
        let result = ProcessRunner.run(
            executableURL: URL(fileURLWithPath: "/bin/ls"),
            arguments: ["/definitely/nonexistent/path/abc123"]
        )

        XCTAssertNil(result, "Command with non-zero exit should return nil")
    }
}

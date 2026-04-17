import Foundation
import AppKit

/// Samples per-process network usage via `nettop` and accumulates deltas per bundle identifier.
final class NetworkMonitor {

    struct Bytes {
        let inBytes: Int64
        let outBytes: Int64
        var total: Int64 { inBytes + outBytes }
    }

    private static let queueKey = DispatchSpecificKey<Void>()

    private var previousSample: [String: Bytes] = [:]
    private var accumulated: [String: Int64] = [:]
    private let queue = DispatchQueue(label: "com.example.iTip.networkMonitor")

    private var timer: DispatchSourceTimer?
    private let resolver = ProcessResolver()

    init() {
        queue.setSpecific(key: Self.queueKey, value: ())
    }

    /// Returns the latest accumulated bytes per bundle identifier (thread-safe, non-blocking).
    func allAccumulatedBytes() -> [String: Int64] {
        withQueueAccess { accumulated }
    }

    /// Starts a repeating timer that samples every `interval` seconds on a background queue.
    func startPolling(interval: TimeInterval = 5.0) {
        withQueueAccess {
            stopPolling()

            let timer = DispatchSource.makeTimerSource(queue: queue)
            timer.schedule(deadline: .now() + interval, repeating: interval)
            timer.setEventHandler { [weak self] in
                self?.performSample()
            }
            timer.resume()
            self.timer = timer
        }
    }

    func stopPolling() {
        withQueueAccess {
            timer?.cancel()
            timer = nil
        }
    }

    // MARK: - Background Sampling

    private func performSample() {
        resolver.refresh()
        let current = sampleProcesses()
        let mapped = mapToBundleIdentifiers(current)

        // `performSample()` is invoked by the timer already running on `queue`.
        // Re-entering the same serial queue with `sync` would deadlock.
        for (bundleID, bytes) in mapped {
            if let prev = previousSample[bundleID] {
                let deltaIn = bytes.inBytes >= prev.inBytes ? bytes.inBytes - prev.inBytes : 0
                let deltaOut = bytes.outBytes >= prev.outBytes ? bytes.outBytes - prev.outBytes : 0
                accumulated[bundleID, default: 0] += deltaIn + deltaOut
            } else {
                accumulated[bundleID, default: 0] += bytes.total
            }
            previousSample[bundleID] = bytes
        }

        let running = Set(mapped.keys)
        previousSample = previousSample.filter { running.contains($0.key) }
    }

    func accumulatedBytes(for bundleIdentifier: String) -> Int64 {
        withQueueAccess {
            accumulated[bundleIdentifier] ?? 0
        }
    }

    private func withQueueAccess<T>(_ operation: () -> T) -> T {
        if DispatchQueue.getSpecific(key: Self.queueKey) != nil {
            return operation()
        }
        return queue.sync(execute: operation)
    }

    // MARK: - Sampling

    private func sampleProcesses() -> [Int: Bytes] {
        guard let data = runNettop() else { return [:] }
        guard let output = String(data: data, encoding: .utf8) else { return [:] }

        var result: [Int: Bytes] = [:]
        let lines = output.split(separator: "\n")

        for line in lines.dropFirst() {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else { continue }

            // nettop -P -x -J bytes_in,bytes_out -l 1 layout:
            // time process_name bytes_in bytes_out
            // process_name may contain spaces; PID is the numeric suffix after the last dot.
            let fields = trimmed.split(separator: " ", omittingEmptySubsequences: true)
            guard fields.count >= 4 else { continue }

            let bytesInStr = String(fields[fields.count - 2])
            let bytesOutStr = String(fields[fields.count - 1])
            let processField = String(fields[fields.count - 3])

            guard let bytesIn = Int64(bytesInStr),
                  let bytesOut = Int64(bytesOutStr),
                  let pid = parsePID(from: processField) else { continue }

            result[pid] = Bytes(inBytes: bytesIn, outBytes: bytesOut)
        }

        return result
    }

    private func runNettop() -> Data? {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/nettop")
        task.arguments = ["-P", "-x", "-J", "bytes_in,bytes_out", "-l", "1"]

        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = Pipe()

        do {
            try task.run()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            task.waitUntilExit()
            return task.terminationStatus == 0 ? data : nil
        } catch {
            return nil
        }
    }

    private func parsePID(from processField: String) -> Int? {
        // Format: "launchd.1", "Google Chrome H.883" — PID is the last dot-separated component.
        processField.split(separator: ".").last.flatMap { Int($0) }
    }

    private func mapToBundleIdentifiers(_ pidBytes: [Int: Bytes]) -> [String: Bytes] {
        var result: [String: Bytes] = [:]
        for (pid, bytes) in pidBytes {
            guard let bundleID = resolver.bundleIdentifier(for: pid) else { continue }
            let existing = result[bundleID] ?? Bytes(inBytes: 0, outBytes: 0)
            result[bundleID] = Bytes(
                inBytes: existing.inBytes + bytes.inBytes,
                outBytes: existing.outBytes + bytes.outBytes
            )
        }
        return result
    }
}

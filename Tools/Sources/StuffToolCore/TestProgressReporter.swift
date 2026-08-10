import Foundation

public struct TestProgressSummary: Equatable, Sendable {
    public let tests: Int
    public let images: Int
    public let failures: Int

    public init(tests: Int, images: Int, failures: Int) {
        self.tests = tests
        self.images = images
        self.failures = failures
    }

    public var matchedTests: Bool {
        tests > 0
    }
}

/// Streams concise Swift Testing progress while retaining the complete raw log.
public actor TestProgressReporter {
    private struct ExpectedCounts: Codable {
        var tests = 0
        var images = 0
    }

    private let scheme: String
    private let heartbeat: TimeInterval
    private let statusURL: URL?
    private let countsURL: URL
    private let countImages: Bool
    private let terminal: any Terminal
    private let fileSystem: any FileSystem
    private let clock: any ToolClock
    private let logHandle: FileHandle
    private let expected: ExpectedCounts
    private let initialWarning: String?

    private var buffers: [CommandOutputStream: [UInt8]] = [:]
    private var startedAt: TimeInterval = 0
    private var lastEmit: TimeInterval = 0
    private var interactive = false
    private var tests = 0
    private var images = 0
    private var failures = 0
    private var suite = ""
    private var current = ""
    private var reportedStatusWriteFailure = false

    public init(
        scheme: String,
        heartbeat: TimeInterval,
        statusURL: URL?,
        countsURL: URL,
        logURL: URL,
        countImages: Bool,
        terminal: any Terminal,
        fileSystem: any FileSystem,
        clock: any ToolClock,
    ) throws {
        self.scheme = scheme
        self.heartbeat = heartbeat
        self.statusURL = statusURL
        self.countsURL = countsURL
        self.countImages = countImages
        self.terminal = terminal
        self.fileSystem = fileSystem
        self.clock = clock
        if fileSystem.kind(of: countsURL) == .missing {
            expected = ExpectedCounts()
            initialWarning = nil
        } else {
            do {
                expected = try JSONDecoder().decode(
                    ExpectedCounts.self,
                    from: fileSystem.read(countsURL),
                )
                initialWarning = nil
            } catch {
                expected = ExpectedCounts()
                initialWarning = "could not read progress counts at \(countsURL.path): \(error)"
            }
        }
        try fileSystem.write(Data(), to: logURL, atomically: false)
        logHandle = try FileHandle(forWritingTo: logURL)
    }

    public func start() async throws {
        startedAt = await clock.now()
        interactive = await terminal.isInteractive()
        if let initialWarning {
            try await warn(initialWarning)
        }
        try await terminal.write(
            "    (progress for \(scheme); full log alongside it in the work directory)\n",
            to: .standardOutput,
        )
    }

    public func consume(_ stream: CommandOutputStream, bytes: [UInt8]) async throws {
        try logHandle.write(contentsOf: Data(bytes))
        var buffer = buffers[stream, default: []]
        buffer.append(contentsOf: bytes)
        while let newline = buffer.firstIndex(of: 10) {
            let lineBytes = buffer[..<newline]
            buffer.removeSubrange(...newline)
            try await consumeLine(String(decoding: lineBytes, as: UTF8.self))
        }
        buffers[stream] = buffer
    }

    public func finish() async throws -> TestProgressSummary {
        for stream in [CommandOutputStream.standardOutput, .standardError] {
            if let bytes = buffers[stream], bytes.isEmpty == false {
                try await consumeLine(String(decoding: bytes, as: UTF8.self))
            }
        }
        buffers.removeAll()
        try logHandle.close()

        if interactive {
            try await terminal.write("\r\u{1B}[K", to: .standardOutput)
        }
        var summary = "    \(tests) tests"
        if images > 0 { summary += ", \(images) images" }
        let elapsed = await elapsed()
        summary += " in \(elapsed)"
        if failures > 0 {
            summary += " — \(failures) failed"
        } else if tests > 0 {
            summary += " — all passed"
        } else {
            summary += " — nothing ran"
            summary += "\n    error: this run matched no tests — check the --only identifier "
            summary += "(Swift Testing filters at Bundle/Suite, not per function)"
        }
        try await terminal.write(summary + "\n", to: .standardOutput)

        if tests > 0 {
            do {
                let data = try JSONEncoder().encode(
                    ExpectedCounts(tests: tests, images: images),
                )
                try fileSystem.write(data, to: countsURL, atomically: true)
            } catch {
                try await warn("could not update progress counts at \(countsURL.path): \(error)")
            }
        }
        let emptyMarker = URL(filePath: countsURL.path + ".empty")
        if tests == 0 {
            do {
                try fileSystem.write(Data("1".utf8), to: emptyMarker, atomically: true)
            } catch {
                try await warn("could not write zero-test marker at \(emptyMarker.path): \(error)")
            }
        } else if fileSystem.kind(of: emptyMarker) != .missing {
            do {
                try fileSystem.removeItem(at: emptyMarker)
            } catch {
                try await warn("could not remove zero-test marker at \(emptyMarker.path): \(error)")
            }
        }
        return TestProgressSummary(tests: tests, images: images, failures: failures)
    }

    private func consumeLine(_ line: String) async throws {
        if countImages, line.hasPrefix("SNAPSHOT_TIMING ") {
            images += 1
            try await emit()
            return
        }
        if let parsed = namedEvent(line, marker: "Suite") {
            if parsed.action.hasPrefix("started") { suite = parsed.name }
            try await emit()
            return
        }
        if let parsed = namedEvent(line, marker: "Test"), parsed.name != "run" {
            if parsed.action.hasPrefix("started") {
                current = parsed.name
                try await emit()
                return
            }
            if parsed.action.hasPrefix("passed") || parsed.action.hasPrefix("failed") {
                tests += 1
                if parsed.action.hasPrefix("failed") {
                    failures += 1
                    if interactive {
                        try await terminal.write("\r\u{1B}[K", to: .standardOutput)
                    }
                    try await terminal.write(
                        "    ✘ \(suite)/\(parsed.name)\n",
                        to: .standardOutput,
                    )
                    try await emit(force: true)
                } else {
                    current = ""
                    try await emit()
                }
                return
            }
        }
        let interesting = [
            "does not match reference",
            "error:",
            "Failure collecting",
            "** TEST SUCCEEDED **",
            "** TEST FAILED **",
        ]
        if interesting.contains(where: line.contains) {
            if interactive {
                try await terminal.write("\r\u{1B}[K", to: .standardOutput)
            }
            try await terminal.write(
                "    \(line.trimmingCharacters(in: .whitespaces))\n",
                to: .standardOutput,
            )
            lastEmit = 0
        }
    }

    private func namedEvent(
        _ line: String,
        marker: String,
    ) -> (name: String, action: String)? {
        guard line.hasPrefix("◇ \(marker) ") || line.hasPrefix("✔ \(marker) ") ||
            line.hasPrefix("✘ \(marker) ")
        else {
            return nil
        }
        let prefix = "◇ \(marker) "
        let passedPrefix = "✔ \(marker) "
        let failedPrefix = "✘ \(marker) "
        let body: Substring = if line.hasPrefix(prefix) {
            line.dropFirst(prefix.count)
        } else if line.hasPrefix(passedPrefix) {
            line.dropFirst(passedPrefix.count)
        } else {
            line.dropFirst(failedPrefix.count)
        }
        guard let separator = body.firstIndex(of: " ") else { return nil }
        return (
            String(body[..<separator]),
            String(body[body.index(after: separator)...]),
        )
    }

    private func emit(force: Bool = false) async throws {
        let now = await clock.now()
        let line = status(now: now)
        if let statusURL {
            do {
                try fileSystem.write(Data((line + "\n").utf8), to: statusURL, atomically: true)
            } catch where reportedStatusWriteFailure == false {
                reportedStatusWriteFailure = true
                try await warn("could not update status file at \(statusURL.path): \(error)")
            } catch {
                // The first failure is already observable; keep progress best effort.
            }
        }
        if interactive {
            try await terminal.write("\r\u{1B}[K\(line)", to: .standardOutput)
        } else if force || now - lastEmit >= heartbeat {
            try await terminal.write(line + "\n", to: .standardOutput)
            lastEmit = now
        }
    }

    private func status(now: TimeInterval) -> String {
        let done: Int
        let total: Int
        let unit: String
        if expected.images > 0, images > 0 {
            done = images
            total = expected.images
            unit = "images"
        } else {
            done = tests
            total = expected.tests
            unit = "tests"
        }
        var parts = ["[\(elapsed(now: now))]"]
        if total > 0, done <= total {
            parts.append("\(done)/\(total) \(unit) (\(100 * done / total)%)")
            if done > 0 {
                let remaining = (now - startedAt) / Double(done) * Double(total - done)
                parts.append("~\(minutesAndSeconds(remaining)) left")
            }
        } else {
            parts.append("\(done) \(unit)")
        }
        if suite.isEmpty == false { parts.append(suite) }
        if current.isEmpty == false { parts.append(current) }
        parts.append(failures > 0 ? "\(failures) failed" : "ok")
        return parts.joined(separator: " · ")
    }

    private func elapsed() async -> String {
        await elapsed(now: clock.now())
    }

    private func elapsed(now: TimeInterval) -> String {
        minutesAndSeconds(now - startedAt)
    }

    private func minutesAndSeconds(_ interval: TimeInterval) -> String {
        let seconds = max(0, Int(interval))
        return "\(seconds / 60):\(String(format: "%02d", seconds % 60))"
    }

    private func warn(_ message: String) async throws {
        try await terminal.write("warning: \(message)\n", to: .standardError)
    }
}

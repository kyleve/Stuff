import ForemanCore
import Foundation
import Testing

struct LogTailReaderTests {
    @Test func missingFileIsNilNotAnError() throws {
        let directory = try makeTemporaryDirectory()
        let url = directory.appendingPathComponent("never-started.log")

        #expect(try LogTailReader.tail(of: url, maxBytes: 1024) == nil)
    }

    @Test func fileSmallerThanTheLimitIsReturnedWhole() throws {
        let directory = try makeTemporaryDirectory()
        let url = directory.appendingPathComponent("worker.log")
        let content = "line one\nline two\n"
        try Data(content.utf8).write(to: url)

        #expect(try LogTailReader.tail(of: url, maxBytes: 1024) == content)
    }

    @Test func truncatedReadStartsOnALineBoundary() throws {
        let directory = try makeTemporaryDirectory()
        let url = directory.appendingPathComponent("worker.log")
        let lines = (1 ... 100).map { "log line number \($0)" }
        try Data(lines.joined(separator: "\n").utf8).write(to: url)

        let tail = try #require(try LogTailReader.tail(of: url, maxBytes: 200))

        #expect(tail.hasSuffix("log line number 100"))
        // No partial first line: the tail must begin exactly at a line start.
        let firstLine = try #require(tail.split(separator: "\n").first)
        #expect(lines.contains(String(firstLine)))
        #expect(tail.utf8.count <= 200)
    }

    @Test func truncatedChunkWithoutANewlineIsReturnedAsIs() throws {
        let directory = try makeTemporaryDirectory()
        let url = directory.appendingPathComponent("worker.log")
        try Data(String(repeating: "x", count: 500).utf8).write(to: url)

        let tail = try #require(try LogTailReader.tail(of: url, maxBytes: 100))

        #expect(tail == String(repeating: "x", count: 100))
    }
}

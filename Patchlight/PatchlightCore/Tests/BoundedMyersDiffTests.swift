import Foundation
import PatchlightCore
import Testing

struct BoundedMyersDiffTests {
    private let engine = BoundedMyersDiff(limits: .githubFallback, contextLineCount: 3)

    @Test func buildsAStableFallbackHunk() throws {
        let base = Data("one\ntwo\nthree\n".utf8)
        let head = Data("one\nsecond\nthree\nfour\n".utf8)

        let hunks = try engine.diff(base: base, head: head, path: "File.swift")

        let hunk = try #require(hunks.first)
        #expect(hunks.count == 1)
        #expect(hunk.lines.map(\.kind) == [.context, .deletion, .addition, .context, .addition])
        #expect(hunk.lines.filter { $0.kind == .addition }.map(\.text) == ["second", "four"])
        #expect(hunk.lines.filter { $0.kind == .deletion }.map(\.text) == ["two"])
    }

    @Test func returnsNoHunksForIdenticalText() throws {
        let data = Data("same\n".utf8)
        #expect(try engine.diff(base: data, head: data, path: "same").isEmpty)
    }

    @Test func rejectsBinaryAndOversizedInputsHonestly() {
        #expect(throws: BoundedMyersDiffError.undecodable) {
            try engine.diff(base: Data([0, 1]), head: Data(), path: "image.png")
        }

        let limits = LineDiffLimits(
            maximumBytesPerSide: 2,
            maximumLinesPerSide: 10,
            maximumWork: 100,
        )
        let bounded = BoundedMyersDiff(limits: limits, contextLineCount: 0)
        #expect(throws: BoundedMyersDiffError.tooLarge(baseBytes: 3, headBytes: 0)) {
            try bounded.diff(base: Data("abc".utf8), head: Data(), path: "large")
        }
    }

    @Test func stopsPathologicalSearchAtTheConfiguredWorkLimit() {
        let limits = LineDiffLimits(
            maximumBytesPerSide: 1024,
            maximumLinesPerSide: 100,
            maximumWork: 2,
        )
        let bounded = BoundedMyersDiff(limits: limits, contextLineCount: 0)
        #expect(throws: BoundedMyersDiffError.workLimitExceeded) {
            try bounded.diff(
                base: Data("a\nb\nc".utf8),
                head: Data("x\ny\nz".utf8),
                path: "hard",
            )
        }
    }
}

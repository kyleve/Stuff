import Foundation
@testable import PortholeCore
import Testing

struct PortholeFramerTests {
    @Test func encodesAndDecodesOneFrame() throws {
        let payload = Data("hello".utf8)
        let frame = try PortholeFraming.encode(payload)
        #expect(frame.count == 4 + payload.count)

        var framer = PortholeFramer()
        let frames = try framer.ingest(frame)
        #expect(frames == [payload])
    }

    @Test func reassemblesAcrossPartialChunks() throws {
        let payload = Data("a longer payload split across chunks".utf8)
        let frame = try PortholeFraming.encode(payload)

        var framer = PortholeFramer()
        // Split mid-header and mid-body.
        #expect(try framer.ingest(frame.prefix(2)).isEmpty)
        #expect(try framer.ingest(frame[2 ..< 6]).isEmpty)
        let frames = try framer.ingest(frame.suffix(from: 6))
        #expect(frames == [payload])
    }

    @Test func emitsMultipleFramesFromOneChunk() throws {
        let a = Data("first".utf8)
        let b = Data("second".utf8)
        var combined = try PortholeFraming.encode(a)
        try combined.append(PortholeFraming.encode(b))

        var framer = PortholeFramer()
        #expect(try framer.ingest(combined) == [a, b])
    }

    @Test func rejectsOversizeLengthPrefixOnDecode() {
        let bogusLength = UInt32(PortholeFraming.maximumFrameByteCount + 1).bigEndian
        var header = Data()
        withUnsafeBytes(of: bogusLength) { header.append(contentsOf: $0) }

        var framer = PortholeFramer()
        #expect(throws: PortholeError.self) {
            try framer.ingest(header)
        }
    }

    @Test func rejectsOversizePayloadOnEncode() {
        let tooBig = Data(count: PortholeFraming.maximumFrameByteCount + 1)
        #expect(throws: PortholeError.self) {
            try PortholeFraming.encode(tooBig)
        }
    }
}

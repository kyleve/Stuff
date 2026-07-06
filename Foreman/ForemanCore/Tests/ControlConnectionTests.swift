import Darwin
@_spi(Testing) import ForemanCore
import Foundation
import Testing

/// Exercises the control-socket wire framing + dispatch over a real connected
/// `socketpair` — the byte-level behavior that the app's `ControlServer` used
/// to hide behind socket setup (line framing, EOF, oversize, malformed input,
/// and a full request→response round trip).
@MainActor
struct ControlConnectionTests {
    /// A connected pair of stream sockets; closed via ``close()``.
    private struct SocketPair {
        let a: Int32
        let b: Int32
        func close() {
            Darwin.close(a)
            Darwin.close(b)
        }
    }

    private func makeSocketPair() throws -> SocketPair {
        var fds = [Int32](repeating: 0, count: 2)
        try #require(socketpair(AF_UNIX, SOCK_STREAM, 0, &fds) == 0)
        return SocketPair(a: fds[0], b: fds[1])
    }

    private func writeRaw(_ string: String, to fd: Int32) {
        let bytes = Array(string.utf8)
        _ = bytes.withUnsafeBytes { Darwin.write(fd, $0.baseAddress, $0.count) }
    }

    // MARK: - Framing

    @Test func readLineReturnsBytesBeforeTheNewline() throws {
        let pair = try makeSocketPair()
        defer { pair.close() }
        writeRaw("hello\n", to: pair.a)
        #expect(ControlConnection.readLine(fd: pair.b) == Data("hello".utf8))
    }

    @Test func readLineFramesConsecutiveLines() throws {
        let pair = try makeSocketPair()
        defer { pair.close() }
        writeRaw("one\ntwo\n", to: pair.a)
        #expect(ControlConnection.readLine(fd: pair.b) == Data("one".utf8))
        #expect(ControlConnection.readLine(fd: pair.b) == Data("two".utf8))
    }

    @Test func readLineReturnsWhatItHasAtEOF() throws {
        let pair = try makeSocketPair()
        defer { pair.close() }
        writeRaw("partial", to: pair.a)
        Darwin.close(pair.a) // EOF without a trailing newline
        #expect(ControlConnection.readLine(fd: pair.b) == Data("partial".utf8))
        Darwin.close(pair.b)
    }

    @Test func readLineRejectsAnOverlongLine() throws {
        let pair = try makeSocketPair()
        defer { pair.close() }
        writeRaw("123456789", to: pair.a) // 9 bytes, no newline
        #expect(ControlConnection.readLine(fd: pair.b, maxBytes: 8) == nil)
    }

    @Test func writeLineAppendsANewline() throws {
        let pair = try makeSocketPair()
        defer { pair.close() }
        ControlConnection.writeLine(fd: pair.a, Data("hi".utf8))
        // readLine returns only if a newline terminated the payload.
        #expect(ControlConnection.readLine(fd: pair.b) == Data("hi".utf8))
    }

    // MARK: - Dispatch

    @Test func respondDispatchesAValidRequest() async throws {
        let fixture = try makeControlServicesFixture(repoNames: ["Main"])
        fixture.services.start()
        let handler = ControlRequestHandler(services: fixture.services)
        let line = try JSONEncoder().encode(ControlRequest.describe)

        let data = await ControlConnection.respond(to: line, handler: handler)
        let response = try JSONDecoder().decode(ControlResponse.self, from: data)
        guard case let .describe(result) = response else {
            Issue.record("expected a describe response, got \(response)")
            return
        }
        #expect(result.repos.map(\.name) == ["Main"])
    }

    @Test func respondEncodesFailureForMalformedInput() async throws {
        let fixture = try makeControlServicesFixture(repoNames: [])
        fixture.services.start()
        let handler = ControlRequestHandler(services: fixture.services)

        let data = await ControlConnection.respond(to: Data("{ not json".utf8), handler: handler)
        let response = try JSONDecoder().decode(ControlResponse.self, from: data)
        guard case let .failure(message) = response else {
            Issue.record("expected a failure response, got \(response)")
            return
        }
        #expect(message.contains("Malformed"))
    }

    @Test func fullRoundTripOverASocketpair() async throws {
        let fixture = try makeControlServicesFixture(repoNames: ["Main"])
        fixture.services.start()
        let handler = ControlRequestHandler(services: fixture.services)
        let pair = try makeSocketPair()
        defer { pair.close() }

        // Client writes a request; the "server" side reads it, dispatches, and
        // writes the reply back; the client reads that — all through the real
        // framing in both directions.
        try ControlConnection.writeLine(fd: pair.a, JSONEncoder().encode(ControlRequest.describe))
        let serverLine = try #require(ControlConnection.readLine(fd: pair.b))
        let reply = await ControlConnection.respond(to: serverLine, handler: handler)
        ControlConnection.writeLine(fd: pair.b, reply)

        let clientLine = try #require(ControlConnection.readLine(fd: pair.a))
        let response = try JSONDecoder().decode(ControlResponse.self, from: clientLine)
        guard case let .describe(result) = response else {
            Issue.record("expected a describe response, got \(response)")
            return
        }
        #expect(result.scanDirectory == fixture.scanDirectory.standardizedFileURL.path)
        #expect(result.repos.map(\.name) == ["Main"])
    }
}

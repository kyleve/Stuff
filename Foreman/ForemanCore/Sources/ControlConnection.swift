import Darwin
import Foundation

/// Newline-delimited-JSON framing and request dispatch for Foreman's control
/// socket, split out from the app's socket server so the wire behavior (line
/// framing, malformed-input handling, response encoding) is unit-testable over
/// a `socketpair` without any socket setup.
///
/// The app's `ControlServer` owns the listening socket, the accept loop, and
/// the connection lifecycle; it delegates every byte to/from a connected file
/// descriptor here.
public enum ControlConnection {
    /// Largest request line accepted before the connection is abandoned.
    public static let defaultMaxLineBytes = 1_048_576

    /// Reads bytes up to (and consuming) a newline from `fd`, returning the
    /// bytes before it. Returns whatever was read so far at EOF, and `nil` on a
    /// read error or when the line exceeds `maxBytes`. Requests are tiny, so a
    /// byte-at-a-time read is fine.
    public static func readLine(fd: Int32, maxBytes: Int = defaultMaxLineBytes) -> Data? {
        var data = Data()
        var byte: UInt8 = 0
        while true {
            let count = read(fd, &byte, 1)
            if count == 1 {
                if byte == 0x0A { return data }
                data.append(byte)
                if data.count > maxBytes { return nil }
            } else if count == 0 {
                return data
            } else if errno == EINTR {
                continue
            } else {
                return nil
            }
        }
    }

    /// Writes `payload` followed by a newline to `fd`, retrying partial writes
    /// and `EINTR`. Best-effort: a write error (e.g. the peer hung up) is
    /// dropped, since there's nothing left to recover.
    public static func writeLine(fd: Int32, _ payload: Data) {
        var data = payload
        data.append(0x0A)
        data.withUnsafeBytes { raw in
            guard var base = raw.bindMemory(to: UInt8.self).baseAddress else { return }
            var remaining = raw.count
            while remaining > 0 {
                let written = Darwin.write(fd, base, remaining)
                if written > 0 {
                    base += written
                    remaining -= written
                } else if written < 0, errno == EINTR {
                    continue
                } else {
                    return
                }
            }
        }
    }

    /// Decodes one request line, runs it through `handler`, and returns the
    /// encoded response (without the trailing newline; ``writeLine(fd:_:)``
    /// adds it). A line that isn't a valid ``ControlRequest`` yields an encoded
    /// `.failure` rather than throwing, so the caller always has a reply to
    /// send and the client never hangs.
    @MainActor
    public static func respond(to line: Data, handler: ControlRequestHandler) async -> Data {
        let request: ControlRequest
        do {
            request = try JSONDecoder().decode(ControlRequest.self, from: line)
        } catch {
            return encode(.failure(message: "Malformed request: \(error.localizedDescription)"))
        }
        return await encode(handler.handle(request))
    }

    /// Encodes a response to JSON, falling back to a minimal failure payload if
    /// encoding itself somehow fails — so a socket write never sends nothing.
    public static func encode(_ response: ControlResponse) -> Data {
        (try? JSONEncoder().encode(response)) ??
            Data(#"{"ok":false,"error":"encoding failed"}"#.utf8)
    }
}

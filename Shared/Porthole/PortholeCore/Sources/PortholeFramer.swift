import Foundation

/// Length-prefixed framing for the Porthole byte stream: each frame is a 4-byte
/// big-endian `UInt32` payload length followed by that many payload bytes.
public enum PortholeFraming {
    /// Frames larger than this are rejected on both encode and decode — a guard
    /// against a corrupt or hostile length prefix allocating unbounded memory.
    public static let maximumFrameByteCount = 32 * 1024 * 1024

    /// Wraps a payload in a length-prefixed frame.
    public static func encode(_ payload: Data) throws -> Data {
        guard payload.count <= maximumFrameByteCount else {
            throw PortholeError.frameTooLarge(payload.count)
        }
        var length = UInt32(payload.count).bigEndian
        var frame = Data(bytes: &length, count: 4)
        frame.append(payload)
        return frame
    }
}

/// A stateful decoder that reassembles whole frames from arbitrarily-chunked
/// stream bytes. Feed it whatever a transport delivers; it emits every complete
/// frame and retains any partial remainder for the next chunk.
///
/// Not thread-safe by design — own one per connection/direction.
public struct PortholeFramer {
    private var buffer = Data()

    public init() {}

    /// Appends `chunk` and returns every frame now complete, in order.
    /// Throws ``PortholeError/frameTooLarge(_:)`` if a length prefix exceeds the
    /// maximum (the stream is then unusable — close it).
    public mutating func ingest(_ chunk: Data) throws -> [Data] {
        buffer.append(chunk)
        var frames: [Data] = []
        while buffer.count >= 4 {
            let frameLength = Int(buffer.prefix(4).reduce(UInt32(0)) { ($0 << 8) | UInt32($1) })
            guard frameLength <= PortholeFraming.maximumFrameByteCount else {
                throw PortholeError.frameTooLarge(frameLength)
            }
            guard buffer.count - 4 >= frameLength else { break }
            let start = buffer.index(buffer.startIndex, offsetBy: 4)
            let end = buffer.index(start, offsetBy: frameLength)
            frames.append(Data(buffer[start ..< end]))
            buffer = Data(buffer[end...])
        }
        return frames
    }
}

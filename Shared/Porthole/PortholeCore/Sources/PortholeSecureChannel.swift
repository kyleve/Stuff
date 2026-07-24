import CryptoKit
import Foundation

/// Wraps any ``PortholeTransport`` in a ChaCha20-Poly1305 record layer keyed by
/// the per-session key. It is itself a `PortholeTransport`, so everything above
/// it is oblivious to encryption.
///
/// The 12-byte nonce is derived, never transmitted: a 4-byte direction tag
/// (`c2d`/`d2c`, so the two directions never share a nonce under the same key)
/// followed by an 8-byte big-endian per-direction counter. Because the receiver
/// reconstructs the nonce from its own strictly-increasing expected counter, any
/// reorder, replay, gap, or tamper yields the wrong nonce (or a bad tag) and the
/// open fails — which finishes the `incoming` stream with an error and closes
/// the connection. Order and integrity thus fall out of the cipher itself.
public final class PortholeSecureChannel: PortholeTransport, @unchecked Sendable {
    public enum Role: Sendable {
        case client
        case device

        var sendTag: [UInt8] {
            switch self {
                case .client: Array("c2d\u{0}".utf8)
                case .device: Array("d2c\u{0}".utf8)
            }
        }

        var receiveTag: [UInt8] {
            switch self {
                case .client: Array("d2c\u{0}".utf8)
                case .device: Array("c2d\u{0}".utf8)
            }
        }
    }

    public let incoming: AsyncThrowingStream<Data, Error>

    private let inner: any PortholeTransport
    private let key: SymmetricKey
    private let sendTag: [UInt8]
    private let sendLock = NSLock()
    private var sendCounter: UInt64 = 0

    public init(wrapping inner: some PortholeTransport, key: SymmetricKey, role: Role) {
        self.inner = inner
        self.key = key
        sendTag = role.sendTag
        let receiveTag = role.receiveTag

        let (stream, continuation) = AsyncThrowingStream<Data, Error>.makeStream()
        incoming = stream

        Task {
            var counter: UInt64 = 0
            do {
                for try await sealed in inner.incoming {
                    let plaintext = try Self.open(
                        sealed,
                        key: key,
                        tag: receiveTag,
                        counter: counter,
                    )
                    counter &+= 1
                    continuation.yield(plaintext)
                }
                continuation.finish()
            } catch {
                continuation.finish(throwing: error)
            }
        }
    }

    public func send(_ frame: Data) async throws {
        let counter = sendLock.withLock { () -> UInt64 in
            let current = sendCounter
            sendCounter &+= 1
            return current
        }

        let nonce = try Self.nonce(tag: sendTag, counter: counter)
        let box = try ChaChaPoly.seal(frame, using: key, nonce: nonce)
        var payload = Data()
        payload.append(box.ciphertext)
        payload.append(box.tag)
        try await inner.send(payload)
    }

    public func close() async {
        await inner.close()
    }

    // MARK: - Record cipher

    /// Poly1305 tag length appended after the ciphertext.
    private static let tagByteCount = 16

    private static func nonce(tag: [UInt8], counter: UInt64) throws -> ChaChaPoly.Nonce {
        var bytes = tag
        withUnsafeBytes(of: counter.bigEndian) { bytes.append(contentsOf: $0) }
        return try ChaChaPoly.Nonce(data: Data(bytes))
    }

    private static func open(
        _ sealed: Data,
        key: SymmetricKey,
        tag: [UInt8],
        counter: UInt64,
    ) throws -> Data {
        guard sealed.count >= tagByteCount else { throw PortholeTransportError.closed }
        let ciphertext = sealed.prefix(sealed.count - tagByteCount)
        let poly1305Tag = sealed.suffix(tagByteCount)
        let nonce = try nonce(tag: tag, counter: counter)
        let box = try ChaChaPoly.SealedBox(nonce: nonce, ciphertext: ciphertext, tag: poly1305Tag)
        return try ChaChaPoly.open(box, using: key)
    }
}

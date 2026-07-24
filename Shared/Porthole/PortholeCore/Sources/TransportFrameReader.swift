import Foundation

/// Serializes a transport's `incoming` stream into pull-based `next()` calls so a
/// plaintext handshake can read a few frames off a connection and then hand the
/// *same* underlying stream to a ``PortholeSecureChannel`` for the encrypted
/// session — without ever creating a second, competing iterator over a
/// single-consumer `AsyncThrowingStream`.
///
/// A background pump owns the one true iterator and feeds a small buffer;
/// `next()` either takes a buffered frame or parks until one arrives (or the
/// stream ends/fails).
public actor TransportFrameReader {
    private var buffer: [Data] = []
    private var waiters: [CheckedContinuation<Data?, Error>] = []
    private var isFinished = false
    private var failure: Error?

    public init(_ transport: some PortholeTransport) {
        let stream = transport.incoming
        Task { await self.pump(stream) }
    }

    /// The next whole frame, or `nil` when the stream has finished. Throws if the
    /// transport failed.
    public func next() async throws -> Data? {
        if !buffer.isEmpty { return buffer.removeFirst() }
        if isFinished {
            if let failure { throw failure }
            return nil
        }
        return try await withCheckedThrowingContinuation { waiters.append($0) }
    }

    private func pump(_ stream: AsyncThrowingStream<Data, Error>) async {
        do {
            for try await frame in stream {
                deliver(frame)
            }
            finish(nil)
        } catch {
            finish(error)
        }
    }

    private func deliver(_ frame: Data) {
        if waiters.isEmpty {
            buffer.append(frame)
        } else {
            waiters.removeFirst().resume(returning: frame)
        }
    }

    private func finish(_ error: Error?) {
        isFinished = true
        failure = error
        for waiter in waiters {
            if let error {
                waiter.resume(throwing: error)
            } else {
                waiter.resume(returning: nil)
            }
        }
        waiters.removeAll()
    }
}

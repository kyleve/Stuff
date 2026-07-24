import Foundation

/// An in-memory ``PortholeTransport`` pair whose two endpoints deliver each
/// other's frames directly — no sockets, no framing, fully deterministic. This
/// is the seam that lets the entire client/device stack (secure channel,
/// pairing, session routing) run end-to-end inside one process in tests.
public final class LoopbackTransport: PortholeTransport, @unchecked Sendable {
    public let incoming: AsyncThrowingStream<Data, Error>
    private let peerContinuation: AsyncThrowingStream<Data, Error>.Continuation
    private let lock = NSLock()
    private var isClosed = false

    private init(
        incoming: AsyncThrowingStream<Data, Error>,
        peerContinuation: AsyncThrowingStream<Data, Error>.Continuation,
    ) {
        self.incoming = incoming
        self.peerContinuation = peerContinuation
    }

    public func send(_ frame: Data) async throws {
        let closed = lock.withLock { isClosed }
        guard !closed else { throw PortholeTransportError.closed }
        peerContinuation.yield(frame)
    }

    public func close() async {
        let shouldFinish = lock.withLock { () -> Bool in
            guard !isClosed else { return false }
            isClosed = true
            return true
        }
        // End the peer's incoming stream; our own end stops when we stop reading.
        if shouldFinish { peerContinuation.finish() }
    }

    /// Creates two connected endpoints: a frame sent on one arrives on the
    /// other's `incoming`.
    public static func makePair() -> (PortholeTransport, PortholeTransport) {
        var continuationA: AsyncThrowingStream<Data, Error>.Continuation!
        let streamA = AsyncThrowingStream<Data, Error> { continuationA = $0 }
        var continuationB: AsyncThrowingStream<Data, Error>.Continuation!
        let streamB = AsyncThrowingStream<Data, Error> { continuationB = $0 }
        let a = LoopbackTransport(incoming: streamA, peerContinuation: continuationB)
        let b = LoopbackTransport(incoming: streamB, peerContinuation: continuationA)
        return (a, b)
    }
}

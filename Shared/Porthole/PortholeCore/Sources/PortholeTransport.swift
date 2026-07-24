import Foundation

/// A bidirectional, frame-oriented byte pipe. Everything above it — the secure
/// channel, the session router, the client — speaks in whole frames and never
/// touches sockets directly, so the same logic runs over a real
/// `NWConnection`-backed transport in production and an in-memory
/// ``LoopbackTransport`` in tests.
///
/// `incoming` yields whole frames (the implementation owns any reassembly). It
/// is single-consumer: iterate it exactly once.
public protocol PortholeTransport: Sendable {
    /// Sends one whole frame. Throws if the transport is closed or the write
    /// fails.
    func send(_ frame: Data) async throws

    /// The stream of whole frames arriving from the peer. Iterate once; it
    /// finishes when the peer closes (or throws on transport failure).
    var incoming: AsyncThrowingStream<Data, Error> { get }

    /// Closes the transport, ending the peer's `incoming` stream.
    func close() async
}

/// Failures a transport can surface directly (protocol-level failures are
/// ``PortholeError``).
public enum PortholeTransportError: Error, Sendable, Equatable {
    case closed
}

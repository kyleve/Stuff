import Foundation
import os
import PortholeCore

/// One connection serializes bounded requests and owns the lifetime of its observation streams.
actor PortholeRemoteClientSession {
    private struct Waiter {
        let requestID: UUID
        let continuation: CheckedContinuation<Void, any Error>
    }

    private final class ObservationControl: Sendable {
        private let stopped = OSAllocatedUnfairLock(initialState: false)
        var isStopped: Bool {
            stopped.withLock { $0 }
        }

        func stop() {
            stopped.withLock { $0 = true }
        }
    }

    private let transport: any PortholeRemoteTransport
    private let log = Logger(subsystem: "com.stuff.porthole", category: "RemoteObservations")
    private var closed = false
    private var exchanging = false
    private var waiters: [Waiter] = []
    private var observations: [PortholeObservationID: ObservationControl] = [:]

    init(transport: any PortholeRemoteTransport) {
        self.transport = transport
    }

    func close() async {
        guard !closed else { return }
        closed = true
        let pending = waiters
        waiters.removeAll()
        for waiter in pending {
            waiter.continuation.resume(throwing: PortholeRemoteError.disconnected)
        }
        // Server session cleanup stops observations even when no stop request can be delivered.
        await transport.close()
    }

    func exchange(_ request: Data) async throws -> Data {
        guard !request.isEmpty else { throw PortholeRemoteError.invalidMessage }
        guard request.count <= PortholeRemoteFraming.maximumBytes
        else { throw PortholeRemoteError.frameTooLarge }
        let requestID = UUID()
        return try await withTaskCancellationHandler {
            try await acquire(requestID: requestID)
            defer { release() }
            try Task.checkCancellation()
            guard !closed else { throw PortholeRemoteError.disconnected }
            return try await transport.exchange(request)
        } onCancel: {
            Task { await self.cancelPending(requestID: requestID) }
        }
    }

    private func acquire(requestID: UUID) async throws {
        try Task.checkCancellation()
        guard !closed else { throw PortholeRemoteError.disconnected }
        guard exchanging else { exchanging = true; return }
        guard waiters.count < 32 else { throw PortholeRemoteError.connectionBusy }
        try await withCheckedThrowingContinuation { continuation in
            waiters.append(Waiter(requestID: requestID, continuation: continuation))
        }
    }

    private func release() {
        if waiters.isEmpty { exchanging = false }
        else { waiters.removeFirst().continuation.resume() }
    }

    private func cancelPending(requestID: UUID) {
        guard let index = waiters.firstIndex(where: { $0.requestID == requestID }) else { return }
        waiters.remove(at: index).continuation.resume(throwing: CancellationError())
    }

    nonisolated func observations(
        client: PortholeRemoteClient,
        invocation: PortholeInvocation,
        interval: Duration,
    ) -> AsyncThrowingStream<PortholeValue, any Error> {
        let observationID = PortholeObservationID(rawValue: UUID())
        let control = ObservationControl()
        return AsyncThrowingStream(bufferingPolicy: .bufferingNewest(1)) { continuation in
            Task {
                await runObservation(
                    client: client,
                    observationID: observationID,
                    invocation: invocation,
                    interval: interval,
                    control: control,
                    continuation: continuation,
                )
            }
            continuation.onTermination = { _ in
                // Do not cancel an in-flight TLS exchange: cancellation closes the connection.
                // The bounded read finishes before the worker sends the shared stop capability.
                control.stop()
            }
        }
    }

    private func runObservation(
        client: PortholeRemoteClient,
        observationID: PortholeObservationID,
        invocation: PortholeInvocation,
        interval: Duration,
        control: ObservationControl,
        continuation: AsyncThrowingStream<PortholeValue, any Error>.Continuation,
    ) async {
        if control.isStopped {
            continuation.finish()
            return
        }
        guard !closed, observations.count < 32 else {
            continuation
                .finish(throwing: closed ? PortholeRemoteError.disconnected : .connectionBusy)
            return
        }
        observations[observationID] = control
        defer { observations[observationID] = nil }
        let reference = PortholeObservationReference(id: observationID, scope: invocation.scope)
        var failure: (any Error)?
        var attemptedStart = false
        do {
            guard interval >= .seconds(1), interval <= .seconds(60)
            else { throw PortholeRemoteError.invalidMessage }
            let components = interval.components
            let milliseconds = Int(components.seconds) * 1000 +
                Int((components.attoseconds + 999_999_999_999_999) / 1_000_000_000_000_000)
            attemptedStart = true
            let started = try await client.startObservation(.init(
                id: observationID,
                invocation: invocation,
                intervalMilliseconds: milliseconds,
            ))
            guard started == reference else { throw PortholeRemoteError.invalidMessage }
            var sequence: Int64?
            while !closed, !control.isStopped {
                let snapshot = try await client.readObservation(
                    reference,
                    afterSequence: sequence,
                    waitMilliseconds: 1000,
                )
                guard snapshot.observation == reference
                else { throw PortholeRemoteError.invalidMessage }
                guard !closed, !control.isStopped else { break }
                switch snapshot.state {
                    case .waiting: break
                    case let .sample(sample):
                        if let sequence {
                            guard sample.sequence >= sequence
                            else { throw PortholeRemoteError.invalidMessage }
                            if sample.sequence == sequence { continue }
                        }
                        sequence = sample.sequence
                        continuation.yield(sample.value)
                    case let .failed(message, _): throw PortholeRemoteError.remoteFailure(message)
                }
            }
        } catch { failure = error }

        if attemptedStart, !closed {
            do { try await client.stopObservation(reference) }
            catch {
                if failure == nil { failure = error }
                log
                    .error(
                        "Remote observation cleanup failed: \(error.localizedDescription, privacy: .public)",
                    )
            }
        }
        if let failure { continuation.finish(throwing: failure) }
        else { continuation.finish() }
    }
}

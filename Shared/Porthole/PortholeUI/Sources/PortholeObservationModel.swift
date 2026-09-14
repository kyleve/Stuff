import Foundation
import Observation
import PortholeRuntime

/// Watches frozen read arguments through the shared executor. The runtime owns sampling;
/// this model only waits for the latest bounded observation and stops it on cancellation.
@MainActor @Observable
final class PortholeObservationModel {
    struct Session {
        let request: PortholeObservationRequest
        let reference: PortholeObservationReference
        var sample: PortholeObservationSample?
        var skippedSamples = false
    }

    enum State {
        case idle
        case starting(Session)
        case watching(Session)
        case stopping(Session)
        case stopped(Session)
        case failed(Session, String)
        case stopFailed(Session, String)

        var session: Session? {
            switch self {
                case .idle: nil
                case let .starting(session), let .watching(session), let .stopping(session),
                     let .stopped(session), let .failed(session, _),
                     let .stopFailed(session, _): session
            }
        }
    }

    private(set) var state: State = .idle
    @ObservationIgnored private var operation: Task<Void, Never>?
    @ObservationIgnored private var client: PortholeObservationClient?

    var isActive: Bool {
        switch state {
            case .starting, .watching, .stopping, .stopFailed: true
            case .idle, .stopped, .failed: false
        }
    }

    var canStop: Bool {
        switch state {
            case .starting, .watching, .stopFailed: true
            case .idle, .stopping, .stopped, .failed: false
        }
    }

    func start(
        invocation: PortholeInvocation,
        execute: @escaping @MainActor (PortholeInvocation) async throws -> PortholeValue,
    ) {
        guard !isActive else { return }
        let observationID = PortholeObservationID(rawValue: UUID())
        let request = PortholeObservationRequest(
            id: observationID,
            invocation: invocation,
            intervalMilliseconds: 1000,
        )
        let session = Session(
            request: request,
            reference: .init(id: observationID, scope: invocation.scope),
        )
        let client = PortholeObservationClient(execute: execute)
        self.client = client
        state = .starting(session)
        operation = Task { [weak self] in
            do {
                let reference = try await client.startObservation(request)
                try Task.checkCancellation()
                guard reference == session.reference else {
                    throw PortholeError
                        .invalidArguments(
                            "The observation reference did not match the requested watch.",
                        )
                }
                guard let self, accepts(reference) else { return }
                state = .watching(session)
                while accepts(reference) {
                    let snapshot = try await client.readObservation(
                        reference,
                        afterSequence: state.session?.sample?.sequence,
                        waitMilliseconds: 10000,
                    )
                    try Task.checkCancellation()
                    guard accepts(reference) else { return }
                    try receive(snapshot)
                }
            } catch is CancellationError {
                if self?.accepts(session.reference) == true { self?.stop() }
            } catch {
                PortholeUILog.failures
                    .error("Observation failed: \(String(describing: error), privacy: .private)")
                if self?.accepts(session.reference) == true {
                    self?.stop(failure: error.localizedDescription)
                }
            }
        }
    }

    func stop() {
        stop(failure: nil)
    }

    private func stop(failure: String?) {
        guard canStop, let session = state.session, let client else { return }
        state = .stopping(session)
        operation?.cancel()
        // Cleanup gets an independent task because the read task may already be cancelled.
        operation = Task { [weak self] in
            do {
                try await client.stopObservation(session.reference)
                guard case let .stopping(current) = self?.state,
                      current.reference == session.reference else { return }
                if let failure { self?.state = .failed(session, failure) }
                else { self?.state = .stopped(session) }
                self?.client = nil
            } catch {
                PortholeUILog.failures
                    .error(
                        "Observation stop failed: \(String(describing: error), privacy: .private)",
                    )
                guard case let .stopping(current) = self?.state,
                      current.reference == session.reference else { return }
                let stopError = "Stop could not be confirmed: \(error.localizedDescription)"
                self?.state = .stopFailed(
                    session,
                    failure.map { "\($0)\n\(stopError)" } ?? stopError,
                )
            }
            self?.operation = nil
        }
    }

    private func accepts(_ reference: PortholeObservationReference) -> Bool {
        switch state {
            case let .starting(session), let .watching(session): session.reference == reference
            case .idle, .stopping, .stopped, .failed, .stopFailed: false
        }
    }

    private func receive(_ snapshot: PortholeObservationSnapshot) throws {
        guard var session = state.session, snapshot.observation == session.reference else {
            throw PortholeError
                .invalidArguments("The observation result belongs to a different watch.")
        }
        switch snapshot.state {
            case .waiting: break
            case let .sample(sample):
                guard sample.sequence > 0 else {
                    throw PortholeError
                        .invalidArguments("The observation sequence must be positive.")
                }
                if let previous = session.sample {
                    guard sample.sequence >= previous.sequence else {
                        throw PortholeError
                            .invalidArguments("The observation sequence moved backwards.")
                    }
                    if sample.sequence - previous.sequence > 1 { session.skippedSamples = true }
                } else if sample.sequence > 1 { session.skippedSamples = true }
                session.sample = sample
                state = .watching(session)
            case let .failed(message, lastSample):
                if let lastSample { session.sample = lastSample }
                state = .watching(session)
                stop(failure: message)
        }
    }
}

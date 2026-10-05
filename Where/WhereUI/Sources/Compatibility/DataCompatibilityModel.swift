import Foundation
import Observation
import PeriscopeCore
import WhereCore

/// The process-owned compatibility observer, including launches with no visible scene.
@MainActor
@Observable
public final class DataCompatibilityModel {
    public enum State: Equatable {
        case checking
        case compatible(DataCompatibilityStatus)
        case updateRequired(DataCompatibilityStatus)
        case verificationFailed(description: String)

        public var allowsData: Bool {
            if case .compatible = self { return true }
            return false
        }

        public var blockingError: DataCompatibilityError? {
            switch self {
                case .checking: .verificationFailed(
                        description: "Compatibility verification is in progress.",
                    )
                case .compatible: nil
                case let .updateRequired(status): .updateRequired(status)
                case let .verificationFailed(description): .verificationFailed(
                        description: description,
                    )
            }
        }
    }

    /// Nil means the user has not chosen to open a data scope yet.
    public private(set) var state: State?
    @ObservationIgnored private var resources: DataCompatibilityServices?
    @ObservationIgnored private var observation: Task<Void, Never>?
    @ObservationIgnored private var onChange: @MainActor (State, Bool) async -> Void = { _, _ in }
    @ObservationIgnored private var generation = UUID()
    @ObservationIgnored private var checking = false
    @ObservationIgnored private var waiters: [CheckedContinuation<Void, Never>] = []

    @ObservationIgnored private var stateWaiters: [UUID: AsyncStream<Void>.Continuation] = [:]

    private static let logger = WhereLog.root(CompatibilityPresentationLog.self)

    public init() {}

    var isAttached: Bool {
        resources != nil
    }

    func attach(
        _ resources: DataCompatibilityServices,
        onChange: @escaping @MainActor (State, Bool) async -> Void,
    ) async {
        guard self.resources == nil else { return }
        self.resources = resources
        self.onChange = onChange
        state = .checking
        let updates = resources.coordinator.updates()
        observation = Task { [weak self] in
            for await _ in updates {
                guard !Task.isCancelled, let self else { return }
                await refresh(publishCapability: false)
            }
        }
        await refresh(publishCapability: true)
    }

    /// Serialization orders suspension and recovery across reentrant store and output awaits.
    func refresh(publishCapability: Bool) async {
        let expectedGeneration = generation
        if checking {
            await withCheckedContinuation { waiters.append($0) }
        } else {
            checking = true
        }
        defer {
            if waiters.isEmpty { checking = false } else { waiters.removeFirst().resume() }
        }
        guard generation == expectedGeneration, let resources else { return }
        let next: State
        do {
            if publishCapability { try await resources.coordinator.publishCapability(at: Date()) }
            let status = try await resources.coordinator.status()
            next = status.isCompatible ? .compatible(status) : .updateRequired(status)
        } catch {
            Self.logger(attachments: [.error(error, name: "compatibility-error")]) {
                .accessBlocked(description: error.localizedDescription)
            }
            next = .verificationFailed(description: error.localizedDescription)
        }
        guard generation == expectedGeneration, !Task.isCancelled else { return }
        guard state != next else { return }
        let recovered = state?.blockingError != nil && state != .checking && next.allowsData
        state = next
        await onChange(next, recovered)
        if !next.allowsData { await resources.outputs.withdraw() }
        guard generation == expectedGeneration else { return }
        for waiter in stateWaiters.values {
            waiter.yield(())
        }
    }

    func fail(_ error: any Error) async {
        let next = State.verificationFailed(description: error.localizedDescription)
        state = next
        await onChange(next, false)
        for waiter in stateWaiters.values {
            waiter.yield(())
        }
    }

    func requireAccess() throws {
        if let error = state?.blockingError { throw error }
    }

    /// Retry an operation whose failure leaves it safe to repeat. Import writes must resolve
    /// their receipt before using this helper to retry anything beyond a confirmed rollback.
    func withAccessRetry<Value>(
        _ operation: @MainActor () async throws -> Value,
    ) async throws -> Value {
        while true {
            try Task.checkCancellation()
            do {
                return try await operation()
            } catch let error as DataCompatibilityError {
                try await waitForRecovery(from: error)
            }
        }
    }

    func waitForRecovery(from error: DataCompatibilityError) async throws {
        switch error {
            case .updateRequired, .invalidMetadata, .verificationFailed:
                await refresh(publishCapability: false)
                try await waitUntilCompatible()
            case .confirmationRequired, .metadataTransactionCannotWriteDomainData:
                throw error
        }
    }

    func waitUntilCompatible() async throws {
        if state?.allowsData == true { return }
        let token = UUID()
        let channel = AsyncStream<Void>.makeStream(bufferingPolicy: .bufferingNewest(1))
        stateWaiters[token] = channel.continuation
        defer {
            stateWaiters.removeValue(forKey: token)?.finish()
        }
        for await _ in channel.stream {
            try Task.checkCancellation()
            if state?.allowsData == true { return }
        }
        throw CancellationError()
    }

    func detach() {
        for waiter in stateWaiters.values {
            waiter.finish()
        }
        stateWaiters.removeAll()
        generation = UUID()
        observation?.cancel()
        observation = nil
        resources = nil
        state = nil
        onChange = { _, _ in }
    }
}

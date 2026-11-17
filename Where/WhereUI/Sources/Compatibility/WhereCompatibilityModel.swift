import Foundation
import LifecycleKit
import Observation
import WhereCore

/// Keeps compatibility alive outside disposable data scopes. Recovery uses the existing launch
/// gate; shutdown uses its serialized teardown, never a second store-owning runtime.
@MainActor
@Observable
public final class WhereCompatibilityModel {
    public let coordinator: DataCompatibilityCoordinator
    @ObservationIgnored public var onBlocked: @MainActor (DataCompatibilityFailure) async
        -> Void = { _ in }
    @ObservationIgnored private var foregroundTask: Task<Void, Never>?
    @ObservationIgnored private var remoteTask: Task<Void, Never>?
    @ObservationIgnored private var retirement: Task<Void, Never>?
    @ObservationIgnored private var wasAllowed = false
    @ObservationIgnored private var waitForNextPoll: @Sendable () async throws -> Void = {
        try await Task.sleep(for: .seconds(60))
    }

    public init(coordinator: DataCompatibilityCoordinator) {
        self.coordinator = coordinator
    }

    isolated deinit {
        foregroundTask?.cancel()
        remoteTask?.cancel()
        retirement?.cancel()
    }

    func bind(model: WhereModel, launcher: LifecycleRunner<WhereSession>) {
        wasAllowed = coordinator.state.allowsStore
        coordinator.onStateChange = { [weak self, weak model, weak launcher] in
            guard let self, let model, let launcher, !model.bypassesCompatibility else { return }
            let previouslyAllowed = wasAllowed
            wasAllowed = coordinator.state.allowsStore
            if case let .blocked(failure) = coordinator.state {
                Task { [weak self] in
                    guard let self, !coordinator.state.allowsStore else { return }
                    await onBlocked(failure)
                    if !previouslyAllowed, !coordinator.state.allowsStore {
                        await model.stopRecordingForCompatibility()
                    }
                }
                if previouslyAllowed {
                    stopScopeObservation()
                    // Teardown also awaits the replacement launch. A second lockout must
                    // retire that scope even while the first task is still draining it.
                    retirement?.cancel()
                    retirement = Task { [weak self, weak model, weak launcher] in
                        guard !Task.isCancelled, let model, let launcher else { return }
                        await model.stopRecordingForCompatibility()
                        guard !Task.isCancelled else { return }
                        await launcher.teardown(
                            WhereLaunch.compatibilityTeardown(for: model),
                            input: (),
                        )
                        guard !Task.isCancelled else { return }
                        self?.retirement = nil
                    }
                }
            }
            if !isBlocking(model),
               launcher.phase.isAwaitingGate(LaunchStepID.compatibility)
            {
                launcher.phase.gateHandle?.complete()
            }
        }
    }

    func isBlocking(_ model: WhereModel) -> Bool {
        guard !model.bypassesCompatibility else { return false }
        // A new installation can choose recording without opening history. Discovery and Finish
        // still require admission; an established viewer has no role-change escape hatch.
        if !model.hasConfirmedRecordingChoice || model.isCompletingOnboarding,
           case .blocked(.recordingDeviceRequired) = coordinator.state { return false }
        return !coordinator.state.allowsStore
    }

    public func refresh(model: WhereModel) async {
        guard !model.bypassesCompatibility else { return }
        await coordinator.refresh { [weak model] in
            guard let model else { throw CancellationError() }
            let context = model.installationRecordingContext
            guard context.automaticRecordingEnabled == true else { return .disabled }
            guard await model.currentLocationAuthorization().allowsBackgroundTracking else {
                return .permissionRequired
            }
            return .recording(context.currentDevice.id)
        }
    }

    func setForeground(_ foreground: Bool, model: WhereModel) {
        foregroundTask?.cancel()
        foregroundTask = nil
        guard foreground else { return }
        foregroundTask = Task { [weak self, weak model] in
            while !Task.isCancelled {
                if let self, let model { await refresh(model: model) }
                else { return }
                guard let wait = self?.waitForNextPoll else { return }
                do { try await wait() }
                catch is CancellationError { return }
                catch { assertionFailure("Unexpected clock failure: \(error)"); return }
            }
        }
    }

    func observeRemoteChanges(services: WhereServices, model: WhereModel) {
        stopScopeObservation()
        let changes = services.remoteDataChangeUpdates()
        remoteTask = Task { [weak self, weak model] in
            for await _ in changes {
                guard !Task.isCancelled else { break }
                if let self, let model { await refresh(model: model) }
                else { break }
            }
        }
    }

    func stopScopeObservation() {
        remoteTask?.cancel()
        remoteTask = nil
    }

    #if DEBUG
        @_spi(Testing) public func setPollWait(
            _ wait: @escaping @Sendable () async throws -> Void,
        ) {
            waitForNextPoll = wait
        }
    #endif
}

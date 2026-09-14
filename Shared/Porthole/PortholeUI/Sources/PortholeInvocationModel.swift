import Foundation
import Observation
import PortholeRuntime

@MainActor @Observable
final class PortholeInvocationModel {
    enum State {
        case idle, running(UUID), succeeded(PortholeValue), approvalRequired(
            PortholeActionProposal,
        ),
            failed(String), cancelled
    }

    let capability: PortholeCapability
    let fields: [PortholeArgumentField]
    let objects: [PortholeObjectReference]
    let scope: PortholeScopeToken
    let observation = PortholeObservationModel()
    var receiverID: UUID?
    private(set) var state: State = .idle
    @ObservationIgnored private var operation: Task<Void, Never>?

    init(
        capability: PortholeCapability,
        objects: [PortholeObjectReference],
        scope: PortholeScopeToken,
    ) {
        self.capability = capability
        self.objects = objects
        self.scope = scope
        fields = capability.parameters.map(PortholeArgumentField.init)
    }

    var isRunning: Bool {
        if case .running = state { true } else { false }
    }

    var isCallable: Bool {
        capability.availability == .callable
    }

    var canWatch: Bool {
        isCallable && capability.effect == .read
    }

    func run(using controller: PortholePresentationController) {
        run(execute: controller.execute)
    }

    func run(execute: @escaping @MainActor (PortholeInvocation) async throws -> PortholeValue) {
        guard !isRunning, !observation.isActive else { return }
        do {
            try perform(invocation(), execute: execute)
        } catch {
            PortholeUILog.failures
                .error(
                    "Invocation arguments failed: \(String(describing: error), privacy: .private)",
                )
            state = .failed(String(describing: error))
        }
    }

    func watch(execute: @escaping @MainActor (PortholeInvocation) async throws -> PortholeValue) {
        guard canWatch, !isRunning, !observation.isActive else { return }
        do { try observation.start(invocation: invocation(), execute: execute) }
        catch {
            PortholeUILog.failures
                .error("Watch arguments failed: \(String(describing: error), privacy: .private)")
            state = .failed(error.localizedDescription)
        }
    }

    private func invocation() throws -> PortholeInvocation {
        let arguments = try Dictionary(uniqueKeysWithValues: fields.map { try ($0.id, $0.value()) })
        return PortholeInvocation(
            id: UUID(),
            scope: scope,
            capabilityID: capability.id,
            receiver: objects.first { $0.id == receiverID },
            arguments: .object(arguments),
        )
    }

    func retryApproved(execute: @escaping @MainActor (PortholeInvocation) async throws
        -> PortholeValue)
    {
        guard case let .approvalRequired(proposal) = state else { return }
        perform(proposal.invocation, execute: execute)
    }

    private func perform(
        _ invocation: PortholeInvocation,
        execute: @escaping @MainActor (PortholeInvocation) async throws -> PortholeValue,
    ) {
        state = .running(invocation.id)
        operation = Task { [weak self] in
            do {
                let result = try await execute(invocation)
                try Task.checkCancellation()
                self?.state = .succeeded(result)
            } catch let PortholeError.approvalRequired(proposal) {
                self?.state = .approvalRequired(proposal)
            } catch is CancellationError { self?.state = .cancelled }
            catch {
                PortholeUILog.failures
                    .error("Invocation failed: \(String(describing: error), privacy: .private)")
                self?.state = .failed(error.localizedDescription)
            }
            self?.operation = nil
        }
    }

    func cancel() {
        operation?.cancel()
        observation.stop()
    }
}

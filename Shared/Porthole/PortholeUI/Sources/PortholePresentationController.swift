import Foundation
import Observation
import PortholeAgent
import PortholeRuntime

/// Keeps the launch context immutable while users navigate live capabilities and evidence.
@MainActor @Observable
public final class PortholePresentationController {
    struct Presentation {
        let id: UUID
        let origin: PortholePresentationOrigin
    }

    struct Snapshot {
        let capabilities: [PortholeCapability]
        let sources: [PortholeSourceFile]
        let contexts: [PortholeContext]
        let objects: [PortholeObjectReference]
    }

    enum LoadState {
        case idle, loading, loaded(Snapshot), failed(String)
    }

    struct PendingApproval {
        let proposal: PortholeActionProposal
        let continuation: CheckedContinuation<Void, Error>
    }

    public let applicationTitle: String
    public let registry: PortholeRegistry
    let console = PortholeConsoleModel()
    public private(set) var agent: PortholeAgentPresentationModel?
    public internal(set) var agentConfigurationError: String?
    public private(set) var host: PortholeHostPresentationModel?
    public private(set) var github: PortholeGitHubPresentationModel?
    public internal(set) var githubConfigurationError: String?
    var githubConfiguration: PortholeGitHubConfiguration?
    var agentInvestigations: PortholeAgentInvestigationLibrary?
    var agentConfiguration: AgentConfiguration?
    struct AgentConfiguration {
        let storageURL: URL
        let keychainService: String
    }

    private var presentation: Presentation?
    @ObservationIgnored private var refreshOperation: RefreshOperation?
    private struct RefreshOperation {
        let id: UUID
        let presentationID: UUID
        let task: Task<Void, Never>
    }

    #if DEBUG
        @ObservationIgnored private var beforeRefresh: (@MainActor () async -> Void)?
        @ObservationIgnored @_spi(Testing) public private(set) var scopeRefreshWaiterCount = 0

        @_spi(Testing)
        public func beforeNextScopeRefresh(_ hook: @escaping @MainActor () async -> Void) {
            beforeRefresh = hook
        }
    #endif
    private var registeredContexts: [PortholeContextID: PortholeContext] = [:]
    private var waiting: [UUID: PendingApproval] = [:]
    private var observedApprovals: [UUID: PortholeActionProposal] = [:]
    private var approving: Set<UUID> = []
    private var observations: [ObjectIdentifier: PortholeObservationModel] = [:]
    @ObservationIgnored private var presentationObservers: [
        ObjectIdentifier: PresentationObserver
    ] =
        [:]
    private struct PresentationObserver {
        weak var value: (any PortholePresentationObserving)?
    }

    private(set) var loadState: LoadState = .idle
    private(set) var breadcrumbs: [PortholeContext] = []
    private(set) var approvalError: String?
    var search = ""

    public init(registry: PortholeRegistry, applicationTitle: String) {
        self.registry = registry
        self.applicationTitle = applicationTitle
    }

    public var origin: PortholePresentationOrigin? {
        presentation?.origin
    }

    public var sessionID: UUID? {
        presentation?.id
    }

    public var isPresented: Bool {
        get { presentation != nil }
        set { if !newValue { dismiss() } }
    }

    var pendingApprovals: [PortholeActionProposal] {
        var proposals = observedApprovals
        for pending in waiting.values {
            proposals[pending.proposal.id] = pending.proposal
        }
        return proposals.values.filter { $0.invocation.scope == origin?.scope }
            .sorted { $0.id.uuidString < $1.id.uuidString }
    }

    var selectedContext: PortholeContext? {
        breadcrumbs.last
    }

    public func present(origin: PortholePresentationOrigin) {
        guard presentation == nil else { return }
        presentation = Presentation(id: UUID(), origin: origin)
        loadState = .idle
        search = ""
        switch origin {
            case let .screen(context):
                breadcrumbs = [context]
                registeredContexts[context.id] = context
            case .application: breadcrumbs = []
        }
        notifyPresentationObservers()
    }

    public func dismiss() {
        let wasPresented = presentation != nil
        cancelRefresh()
        console.cancel()
        agent?.cancel()
        for observation in observations.values {
            observation.stop()
        }
        observations.removeAll()
        presentation = nil
        for operationID in Array(waiting.keys) {
            reject(operationID: operationID)
        }
        if wasPresented { notifyPresentationObservers() }
    }

    func registerPresentationObserver(_ observer: any PortholePresentationObserving) {
        presentationObservers = presentationObservers.filter { $0.value.value != nil }
        presentationObservers[ObjectIdentifier(observer)] = PresentationObserver(value: observer)
    }

    func unregisterPresentationObserver(_ observer: any PortholePresentationObserving) {
        presentationObservers[ObjectIdentifier(observer)] = nil
    }

    private func notifyPresentationObservers() {
        presentationObservers = presentationObservers.filter { $0.value.value != nil }
        let observers = presentationObservers.values.compactMap(\.value)
        for observer in observers {
            observer.portholePresentationDidChange()
        }
    }

    func registerObservation(_ observation: PortholeObservationModel) {
        guard isPresented else { observation.stop(); return }
        observations[ObjectIdentifier(observation)] = observation
    }

    func unregisterObservation(_ observation: PortholeObservationModel) {
        observations[ObjectIdentifier(observation)] = nil
        observation.stop()
    }

    public func registerContexts(_ contexts: [PortholeContext]) {
        for context in contexts {
            registeredContexts[context.id] = context
        }
    }

    public func attachAgent(model: PortholeAgentPresentationModel) {
        agent?.cancel()
        agent = model
        agentConfigurationError = nil
    }

    func agentConfigurationFailed(_ error: any Error) {
        agent?.cancel()
        agent = nil
        agentConfigurationError = error.localizedDescription
    }

    public func attachHost(model: PortholeHostPresentationModel) {
        if let host, host !== model {
            switch host.state {
                case .disabled, .failed: break
                case .creating, .starting, .active:
                    preconditionFailure("Disable the previous remote host before replacing it")
            }
        }
        host = model
    }

    public func attachGitHub(model: PortholeGitHubPresentationModel) {
        github = model
    }

    func navigate(to context: PortholeContext) {
        guard context.scope == origin?.scope else { return }
        if let index = breadcrumbs.firstIndex(where: { $0.id == context.id }) {
            breadcrumbs = Array(breadcrumbs.prefix(index + 1))
        } else {
            breadcrumbs.append(context)
        }
    }

    /// Attachment callers join one presentation-owned read. Cancelling one caller leaves
    /// other attached readers intact; dismissal and explicit refresh cancel the owned task.
    func refreshIfNeeded() async {
        guard !Task.isCancelled, let presentation else { return }
        if let operation = refreshOperation, operation.presentationID == presentation.id {
            await waitForRefresh(operation)
            return
        }
        switch loadState {
            case .idle, .loading:
                await waitForRefresh(startRefresh(presentation))
            case .loaded, .failed: return
        }
    }

    func refresh() async {
        guard !Task.isCancelled, let presentation else { return }
        await waitForRefresh(startRefresh(presentation))
    }

    private func startRefresh(_ presentation: Presentation) -> RefreshOperation {
        cancelRefresh()
        let operationID = UUID()
        let operation = RefreshOperation(
            id: operationID,
            presentationID: presentation.id,
            task: Task { [self] in
                await readScope(presentation: presentation, operationID: operationID)
            },
        )
        refreshOperation = operation
        loadState = .loading
        return operation
    }

    private func waitForRefresh(_ operation: RefreshOperation) async {
        #if DEBUG
            scopeRefreshWaiterCount += 1
            defer { scopeRefreshWaiterCount -= 1 }
        #endif
        await operation.task.value
    }

    private func cancelRefresh() {
        let operation = refreshOperation
        refreshOperation = nil
        operation?.task.cancel()
        if case .loading = loadState { loadState = .idle }
    }

    private func readScope(presentation: Presentation, operationID: UUID) async {
        defer {
            if refreshOperation?.id == operationID { refreshOperation = nil }
        }
        do {
            #if DEBUG
                if let hook = beforeRefresh {
                    beforeRefresh = nil
                    await hook()
                }
            #endif
            try Task.checkCancellation()
            let scope = presentation.origin.scope
            let capabilities = try await registry.capabilities(in: scope)
            let sources = try await registry.sourceFiles(in: scope)
            let contexts = try await registry.capturedContexts(in: scope)
            let objects = try await registry.objectReferences(in: scope)
            try Task.checkCancellation()
            guard self.presentation?.id == presentation.id,
                  refreshOperation?.id == operationID else { return }
            registerContexts(contexts)
            loadState = .loaded(Snapshot(
                capabilities: capabilities,
                sources: sources,
                contexts: registeredContexts.values
                    .filter { $0.scope == scope }
                    .sorted { $0.title < $1.title },
                objects: objects,
            ))
        } catch is CancellationError {
            if self.presentation?.id == presentation.id,
               refreshOperation?.id == operationID { loadState = .idle }
        } catch {
            guard self.presentation?.id == presentation.id,
                  refreshOperation?.id == operationID else { return }
            PortholeUILog.failures
                .error("Scope refresh failed: \(String(describing: error), privacy: .private)")
            loadState = .failed(String(describing: error))
        }
    }

    /// Untrusted clients can request calls, but only the review UI can grant approval.
    public func execute(_ invocation: PortholeInvocation) async throws -> PortholeValue {
        try Task.checkCancellation()
        do {
            return try await registry.invoke(invocation)
        } catch let PortholeError.approvalRequired(proposal) {
            try await waitForApproval(proposal)
            try Task.checkCancellation()
            return try await registry.invoke(invocation)
        }
    }

    func approve(_ proposal: PortholeActionProposal) async {
        guard pendingApprovals.contains(proposal),
              approving.insert(proposal.id).inserted else { return }
        defer { approving.remove(proposal.id) }
        let hadLocalWaiter = waiting[proposal.id] != nil
        do {
            try await registry.approve(proposal)
            observedApprovals[proposal.id] = nil
            approvalError = nil
            if let pending = waiting.removeValue(forKey: proposal.id) {
                pending.continuation.resume()
            } else if hadLocalWaiter { await registry.reject(operationID: proposal.id) }
        } catch {
            PortholeUILog.failures
                .error("Approval failed: \(String(describing: error), privacy: .private)")
            approvalError = String(describing: error)
            if let pending = waiting.removeValue(forKey: proposal.id) {
                pending.continuation.resume(throwing: error)
            }
        }
    }

    func reject(operationID: UUID) {
        observedApprovals[operationID] = nil
        if let pending = waiting.removeValue(forKey: operationID) {
            pending.continuation.resume(throwing: CancellationError())
        }
        Task { await registry.reject(operationID: operationID) }
    }

    func refreshApprovals() async {
        let trackedWaiters = Set(waiting.keys)
        let proposals = await registry.pendingApprovals()
        observedApprovals = Dictionary(uniqueKeysWithValues: proposals.map { ($0.id, $0) })
        for operationID in trackedWaiters
            where observedApprovals[operationID] == nil && !approving.contains(operationID)
        {
            if let pending = waiting.removeValue(forKey: operationID) {
                pending.continuation
                    .resume(throwing: PortholeError
                        .operationFailed(
                            "The approval is no longer available. The scope may have changed or Porthole was disabled.",
                        ))
            }
        }
    }

    func observeApprovals() async {
        let sessionID = sessionID
        do {
            while !Task.isCancelled, self.sessionID == sessionID {
                await refreshApprovals()
                try await ContinuousClock().sleep(for: .milliseconds(500))
            }
        } catch is CancellationError {
            return
        } catch {
            PortholeUILog.failures
                .error(
                    "Approval observation failed: \(String(describing: error), privacy: .private)",
                )
            approvalError = String(describing: error)
        }
    }

    private func waitForApproval(_ proposal: PortholeActionProposal) async throws {
        try await withTaskCancellationHandler {
            try Task.checkCancellation()
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<
                Void,
                Error
            >) in
                guard waiting[proposal.id] == nil else {
                    continuation.resume(throwing: PortholeError.operationInProgress)
                    return
                }
                waiting[proposal.id] = PendingApproval(
                    proposal: proposal,
                    continuation: continuation,
                )
            }
        } onCancel: {
            Task { @MainActor [weak self] in self?.reject(operationID: proposal.id) }
        }
    }
}

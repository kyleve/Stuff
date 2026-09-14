import Foundation
import Observation
import OSLog
import PortholeAgent

/// Owns chat controls and mirrors the durable native transcript without exposing credentials.
@MainActor @Observable
public final class PortholeAgentPresentationModel {
    struct Progress {
        var text = ""
        var reasoning = ""
        var toolCalls: [PortholeAgentInvocation] = []
    }

    enum State {
        case ready
        case running(Progress)
        case failed(String)
        case needsReview(Review)
    }

    struct Review {
        let operations: [PortholeAgentOperation]
        var note: String?
    }

    public typealias Reconcile = @Sendable (PortholeAgentInvocation) async throws
        -> PortholeAgentToolResult?

    private let sessions: any PortholeAgentSessionCreating
    private let credentials: any PortholeAgentCredentialEditing
    private let journal: PortholeAgentJournal
    private let instructions: String
    private let reconcile: Reconcile
    private var activeSession: (any PortholeAgentStreaming)?
    private var consentingProviders: Set<PortholeAgentProvider> = []
    private var restoredModel = false
    private(set) var investigation: PortholeAgentInvestigationControls?
    private(set) var runs: [PortholeAgentRunIdentity] = []
    private(set) var executionOrigin: PortholeAgentOrigin?
    private(set) var history: [PortholeAgentMessage] = []
    private(set) var state: State = .ready
    private(set) var provider: PortholeAgentProvider
    var modelID: String
    var apiKey = ""
    var prompt = ""

    public init(
        sessions: any PortholeAgentSessionCreating,
        credentials: any PortholeAgentCredentialEditing,
        journal: PortholeAgentJournal,
        initialProvider: PortholeAgentProvider,
        initialModelID: String,
        instructions: String,
        reconcile: @escaping Reconcile,
    ) {
        self.sessions = sessions
        self.credentials = credentials
        self.journal = journal
        provider = initialProvider
        modelID = initialModelID
        self.instructions = instructions
        self.reconcile = reconcile
    }

    var selectedProvider: PortholeAgentProvider {
        get { provider }
        set {
            guard provider != newValue, !isRunning else { return }
            provider = newValue
            modelID = ""
            apiKey = ""
        }
    }

    var hasConsent: Bool {
        consentingProviders.contains(provider)
    }

    var isRunning: Bool {
        if case .running = state { true } else { false }
    }

    var canSend: Bool {
        guard !isRunning, hasConsent,
              hasLiveScope,
              !modelID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return false }
        if case .needsReview = state { return false }
        return true
    }

    var hasLiveScope: Bool {
        guard let investigation else { return true }
        return (executionOrigin ?? investigation.selected.origin).scope == investigation
            .currentCapture.scope
    }

    func load() async {
        guard !isRunning else { return }
        let snapshot = await journal.snapshot()
        runs = snapshot.runs
        executionOrigin = snapshot.contextChanges.last?.origin ?? snapshot.originalOrigin
        if !restoredModel {
            restoredModel = true
            if let model = snapshot.runs.last?.model {
                provider = model.provider
                modelID = model.modelID
            }
        }
        consentingProviders = snapshot.consentingProviders
        history = snapshot.messages
        let unresolved = snapshot.operations.filter {
            switch $0.state {
                case .proposed, .executing, .uncertain: true
                case .completed, .acknowledgedUncertain: false
            }
        }
        if !unresolved.isEmpty { state = .needsReview(Review(operations: unresolved)) }
        else {
            do {
                history = try await journal.resumeMessages()
                state = .ready
            } catch { report(error) }
        }
    }

    func saveKey() {
        do {
            try credentials.store(apiKey: apiKey, for: provider)
            apiKey = ""
        } catch { report(error) }
    }

    func removeKey() {
        do {
            try credentials.remove(for: provider)
            apiKey = ""
        } catch { report(error) }
    }

    func setConsent(granted: Bool) async {
        if !granted { cancel() }
        do {
            try await journal.setConsent(for: provider, granted: granted)
            consentingProviders = await journal.snapshot().consentingProviders
        } catch { report(error) }
    }

    func send() async {
        guard canSend else { return }
        state = .running(Progress())
        do {
            let messages = try await journal.resumeMessages() + [.user(text: prompt)]
            let session = try sessions.create(configuration: PortholeAgentConfiguration(
                provider: provider,
                modelID: modelID,
                instructions: instructions,
                maxSteps: 12,
                maxOutputTokens: 4096,
                duration: .seconds(300),
            ))
            activeSession = session
            history = messages
            prompt = ""
            defer { activeSession = nil }
            for try await event in session.stream(messages: messages) {
                try Task.checkCancellation()
                consume(event)
            }
            await loadAfterRun(error: nil)
        } catch is CancellationError {
            await loadAfterRun(error: "Stopped. Inspect unresolved operations before continuing.")
        } catch {
            PortholeUILog.failures
                .error("AI run failed: \(String(describing: error), privacy: .private)")
            await loadAfterRun(error: String(describing: error))
        }
    }

    public func cancel() {
        activeSession?.cancel()
    }

    func attachInvestigation(_ controls: PortholeAgentInvestigationControls) {
        investigation = controls
    }

    func newInvestigation() {
        guard !isRunning else { return }
        do { try investigation?.create() } catch { report(error) }
    }

    func resumeInvestigation(_ investigationID: UUID) {
        guard !isRunning else { return }
        do { try investigation?.resume(investigationID) } catch { report(error) }
    }

    func continueWithCurrentContext() async {
        guard !isRunning else { return }
        do {
            try await investigation?.continueWithContext()
            await load()
        } catch { report(error) }
    }

    func checkOutcome(_ operation: PortholeAgentOperation) async {
        do {
            guard let result = try await reconcile(operation.invocation) else {
                if case var .needsReview(review) = state {
                    review.note = "The runtime has no confirmed result."
                    state = .needsReview(review)
                }
                return
            }
            try await journal.reconcile(
                operationID: operation.invocation.operationID,
                result: result,
            )
            await load()
        } catch { report(error) }
    }

    func acknowledgeUncertainty(_ operation: PortholeAgentOperation) async {
        do {
            try await journal.acknowledgeUncertainty(operationID: operation.invocation.operationID)
            await load()
        } catch { report(error) }
    }

    private func consume(_ event: PortholeAgentEvent) {
        guard case var .running(progress) = state else { return }
        switch event {
            case let .text(delta): progress.text += delta
            case let .reasoning(delta): progress.reasoning += delta
            case let .toolCall(invocation): progress.toolCalls.append(invocation)
            case let .message(message):
                history.append(message)
                if case .assistant = message { progress.text = ""; progress.toolCalls = [] }
            case .started, .stepStarted, .toolInputStarted, .toolInputDelta, .toolResult,
                 .stepFinished, .finished: break
        }
        state = .running(progress)
    }

    private func loadAfterRun(error: String?) async {
        state = .ready
        await load()
        if case .ready = state, let error { state = .failed(error) }
    }

    private func report(_ error: any Error) {
        let message = String(describing: error)
        PortholeUILog.failures.error("AI debugger failed: \(message, privacy: .private)")
        if case var .needsReview(review) = state {
            review.note = message
            state = .needsReview(review)
        } else {
            state = .failed(message)
        }
    }
}

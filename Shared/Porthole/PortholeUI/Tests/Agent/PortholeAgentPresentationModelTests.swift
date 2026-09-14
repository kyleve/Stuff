import Foundation
@testable import PortholeAgent
import PortholeCore
@testable import PortholeUI
import Testing

@MainActor
struct PortholeAgentPresentationModelTests {
    @Test func savesKeyAndScopesConsentToProvider() async throws {
        let journal = try PortholeAgentJournal(storage: AgentUITestStorage())
        let credentials = AgentUITestCredentials()
        let factory = AgentUITestFactory(session: AgentUITestSession(
            journal: journal,
            suspend: false,
        ))
        let model = makeModel(factory: factory, credentials: credentials, journal: journal)
        model.apiKey = "private-test-key"
        model.saveKey()
        #expect(model.apiKey.isEmpty)
        #expect(try credentials.apiKey(for: .openAI) == "private-test-key")
        await model.setConsent(granted: true)
        #expect(model.hasConsent)
        model.selectedProvider = .anthropic
        #expect(!model.hasConsent)
        #expect(model.modelID.isEmpty)
    }

    @Test func sendsExplicitModelAndRestoresSavedAnswer() async throws {
        let journal = try PortholeAgentJournal(storage: AgentUITestStorage())
        let credentials = AgentUITestCredentials()
        let factory = AgentUITestFactory(session: AgentUITestSession(
            journal: journal,
            suspend: false,
        ))
        let model = makeModel(factory: factory, credentials: credentials, journal: journal)
        await model.setConsent(granted: true)
        model.prompt = "Why wasn't this a flight?"
        await model.send()
        #expect(factory.configurations.first?.modelID == "explicit-test-model")
        #expect(model.history == [
            .user(text: "Why wasn't this a flight?"),
            .assistant(text: "A recorded diagnostic.", toolCalls: []),
        ])
        #expect(!model.isRunning)
    }

    @Test(.timeLimit(.minutes(1))) func stopsTheActiveNativeSession() async throws {
        let journal = try PortholeAgentJournal(storage: AgentUITestStorage())
        let credentials = AgentUITestCredentials()
        let session = AgentUITestSession(journal: journal, suspend: true)
        let factory = AgentUITestFactory(session: session)
        let model = makeModel(factory: factory, credentials: credentials, journal: journal)
        await model.setConsent(granted: true)
        model.prompt = "Inspect"
        let running = Task { await model.send() }
        var started = session.started.stream.makeAsyncIterator()
        #expect(await started.next() == true)
        #expect(model.isRunning)
        #expect(!model.canSend)
        model.cancel()
        await running.value
        #expect(!model.isRunning)
        #expect(factory.configurations.count == 1)
    }

    @Test func unresolvedOperationsDisableSend() async throws {
        let journal = try PortholeAgentJournal(storage: AgentUITestStorage())
        let invocation = try await journal.register(
            runID: UUID(),
            callID: .init(rawValue: "call"),
            toolID: .init(rawValue: "invoke"),
            arguments: .object([:]),
        )
        _ = try await journal.begin(invocation)
        try await journal.setConsent(for: .openAI, granted: true)
        let credentials = AgentUITestCredentials()
        let factory = AgentUITestFactory(session: AgentUITestSession(
            journal: journal,
            suspend: false,
        ))
        let model = makeModel(factory: factory, credentials: credentials, journal: journal)
        model.prompt = "Continue"
        await model.load()
        #expect(!model.canSend)
        await model.send()
        #expect(factory.configurations.isEmpty)
    }

    private func makeModel(
        factory: AgentUITestFactory,
        credentials: AgentUITestCredentials,
        journal: PortholeAgentJournal,
    ) -> PortholeAgentPresentationModel {
        PortholeAgentPresentationModel(
            sessions: factory,
            credentials: credentials,
            journal: journal,
            initialProvider: .openAI,
            initialModelID: "explicit-test-model",
            instructions: "Inspect the captured context.",
            reconcile: { _ in nil },
        )
    }
}

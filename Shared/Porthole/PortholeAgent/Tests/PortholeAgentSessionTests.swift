import AI
import Foundation
@_spi(Testing) @testable import PortholeAgent
import PortholeCore
import Synchronization
import Testing

struct PortholeAgentSessionTests {
    @Test func persistsAndRestoresCompleteToolHistory() async throws {
        let workspace = try AgentTestWorkspace()
        let journal = try PortholeAgentJournal(url: workspace.journalURL)
        try await journal.setConsent(for: .openAI, granted: true)
        let model = ScriptedAgentModel(steps: [
            [
                .toolCall(ToolCall(id: "call-1", name: "inspect", arguments: .object([:]))),
                .finish(reason: .toolCalls, usage: Usage()),
            ],
            [
                .textDelta("The evidence explains it."),
                .finish(reason: .stop, usage: Usage(inputTokens: 4, outputTokens: 5)),
            ],
        ])
        let invocations = Mutex<[PortholeAgentInvocation]>([])
        let session = try PortholeAgentSession(
            model: model,
            configuration: agentTestConfiguration(),
            tools: [agentTestTool()],
            journal: journal,
            redaction: .init(secrets: []),
            executor: { invocation in
                invocations.withLock { $0.append(invocation) }
                return .object(["evidence": .integer(42)])
            },
        )
        var events: [PortholeAgentEvent] = []
        for try await event in session
            .stream(messages: [.user(text: "Why?")])
        {
            events.append(event)
        }
        #expect(invocations.withLock { $0.count } == 1)
        let recorded = try #require(invocations.withLock { $0.first })
        let restored = try PortholeAgentJournal(url: workspace.journalURL)
        let messages = try await restored.resumeMessages()
        #expect(messages.count == 4)
        guard case let .assistant(_, calls) = messages[1],
              case let .tool(results) = messages[2]
        else {
            Issue.record("Expected assistant tool call and tool result messages")
            return
        }
        #expect(calls.first?.operationID == recorded.operationID)
        #expect(results.first?.output == .object(["evidence": .integer(42)]))
        let nextModel = ScriptedAgentModel(steps: [[
            .textDelta("Continued."),
            .finish(reason: .stop, usage: Usage()),
        ]])
        let next = try PortholeAgentSession(
            model: nextModel,
            configuration: agentTestConfiguration(),
            tools: [agentTestTool()],
            journal: restored,
            redaction: .init(secrets: []),
            executor: { _ in
                Issue.record("A restored tool call must not execute again")
                return .null
            },
        )
        for try await _ in next.stream(messages: messages + [.user(text: "Continue")]) {}
        #expect(nextModel.requests.first?.messages.contains(where: { $0.role == .tool }) == true)
        #expect(events.contains { if case .finished = $0 { true } else { false } })

        // Astra rejects sampling parameters. Preserve provider defaults across all three requests.
        let initialRequests = model.requests
        let resumedRequests = nextModel.requests
        #expect(initialRequests.count == 2)
        #expect(resumedRequests.count == 1)
        for request in initialRequests + resumedRequests {
            #expect(request.temperature == nil)
            #expect(request.topP == nil)
            #expect(request.reasoning == .providerDefault)
            #expect(request.providerOptions == nil)
        }
    }

    @Test func toolFailureStopsModelAndBlocksResume() async throws {
        let workspace = try AgentTestWorkspace()
        let journal = try PortholeAgentJournal(url: workspace.journalURL)
        try await journal.setConsent(for: .openAI, granted: true)
        let model = ScriptedAgentModel(steps: [[
            .toolCall(ToolCall(id: "write-1", name: "inspect", arguments: .object([:]))),
            .finish(reason: .toolCalls, usage: Usage()),
        ]])
        let session = try PortholeAgentSession(
            model: model,
            configuration: agentTestConfiguration(),
            tools: [agentTestTool()],
            journal: journal,
            redaction: .init(secrets: []),
            executor: { _ in throw PortholeAgentError.toolFailed("Uncertain write") },
        )
        await #expect(throws: PortholeAgentError.toolFailed("Uncertain write")) {
            for try await _ in session.stream(messages: [.user(text: "Inspect")]) {}
        }
        #expect(model.requests.count == 1)
        let record = try #require(await journal.snapshot().operations.first)
        await #expect(throws: PortholeAgentError
            .operationUnresolved(record.invocation.operationID))
        {
            try await journal.resumeMessages()
        }
    }

    @Test func requiresConsentForTheSelectedProvider() async throws {
        let workspace = try AgentTestWorkspace()
        let journal = try PortholeAgentJournal(url: workspace.journalURL)
        try await journal.setConsent(for: .openAI, granted: true)
        let model = ScriptedAgentModel(steps: [])
        let session = try PortholeAgentSession(
            model: model,
            configuration: agentTestConfiguration(provider: .anthropic),
            tools: [],
            journal: journal,
            redaction: .init(secrets: []),
            executor: { _ in .null },
        )
        await #expect(throws: PortholeAgentError.consentRequired(.anthropic)) {
            for try await _ in session.stream(messages: [.user(text: "Inspect")]) {}
        }
        #expect(model.requests.isEmpty)
    }

    @Test func redactsSecretsSplitAcrossProviderChunks() async throws {
        let workspace = try AgentTestWorkspace()
        let journal = try PortholeAgentJournal(url: workspace.journalURL)
        try await journal.setConsent(for: .openAI, granted: true)
        let model = ScriptedAgentModel(steps: [[
            .textDelta("The se"),
            .textDelta("cret-key is hidden."),
            .finish(reason: .stop, usage: Usage()),
        ]])
        let session = try PortholeAgentSession(
            model: model,
            configuration: agentTestConfiguration(),
            tools: [],
            journal: journal,
            redaction: .init(secrets: ["secret-key"]),
            executor: { _ in .null },
        )
        var text = ""
        for try await event in session.stream(messages: [.user(text: "Inspect secret-key")]) {
            if case let .text(delta) = event { text += delta }
        }
        #expect(text == "The [REDACTED] is hidden.")
        #expect(model.requests.first?.messages
            .contains(where: { $0.content.contains(.text("Inspect [REDACTED]")) }) == true)
        let persisted = try String(contentsOf: workspace.journalURL, encoding: .utf8)
        #expect(!persisted.contains("secret-key"))
    }
}

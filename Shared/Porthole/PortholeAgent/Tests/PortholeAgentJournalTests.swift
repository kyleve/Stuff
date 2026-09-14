import Foundation
@testable import PortholeAgent
import PortholeCore
import Testing

struct PortholeAgentJournalTests {
    @Test func reopenedPresentationCannotOverlapOrRecaptureActiveJournal() async throws {
        let workspace = try AgentTestWorkspace()
        let journal = try PortholeAgentJournal(url: workspace.journalURL)
        let first = UUID()
        let next = UUID()
        try await journal.claim(runID: first)
        await #expect(throws: PortholeAgentError.busy) { try await journal.claim(runID: next) }
        await #expect(throws: PortholeAgentError.busy) {
            try await journal.continueWithContext(
                .application(scope: .init(id: .init(rawValue: "app"), generation: UUID())),
                provenance: .null,
            )
        }
        await journal.release(runID: next)
        await #expect(throws: PortholeAgentError.busy) { try await journal.claim(runID: next) }
        await journal.release(runID: first)
        try await journal.claim(runID: next)
    }

    @Test func explicitlyAdoptsNewScopeWithoutChangingOriginalEvidence() async throws {
        let first = PortholeAgentOrigin.application(scope: .init(
            id: .init(rawValue: "app"),
            generation: UUID(),
        ))
        let next = PortholeAgentOrigin.application(scope: .init(
            id: .init(rawValue: "app"),
            generation: UUID(),
        ))
        let workspace = try AgentTestWorkspace()
        let journal = try PortholeAgentJournal(
            storage: PortholeAgentFileTranscriptStore(url: workspace.journalURL),
            originalOrigin: first,
        )
        try await journal.prepare(messages: [.user(text: "Original issue")])
        try await journal.continueWithContext(
            next,
            provenance: .object(["sourceArchiveSHA256": .string("new-source-hash")]),
        )
        let restored = try PortholeAgentJournal(url: workspace.journalURL)
        #expect(restored.originalOrigin == first)
        #expect(await restored.executionOrigin() == next)
        let history = try await restored.resumeMessages()
        #expect(history.first == .user(text: "Original issue"))
        guard case let .user(text) = try #require(history.last)
        else { Issue.record("Expected explicit context change"); return }
        #expect(text.contains("new-source-hash"))
        #expect(text.contains("Earlier handles are not translated"))
    }

    @Test func contextChangeCannotBypassUncertainOperation() async throws {
        let workspace = try AgentTestWorkspace()
        let journal = try PortholeAgentJournal(url: workspace.journalURL)
        let invocation = try await journal.register(
            runID: UUID(),
            callID: .init(rawValue: "call"),
            toolID: .init(rawValue: "write"),
            arguments: .object([:]),
        )
        await #expect(throws: PortholeAgentError.operationUnresolved(invocation.operationID)) {
            try await journal.continueWithContext(
                .application(scope: .init(id: .init(rawValue: "app"), generation: UUID())),
                provenance: .null,
            )
        }
        #expect(await journal.snapshot().contextChanges.isEmpty)
    }

    @Test func acknowledgementKeepsUnknownOutcomeAndNeverReplays() async throws {
        let workspace = try AgentTestWorkspace()
        let journal = try PortholeAgentJournal(url: workspace.journalURL)
        let invocation = try await journal.register(
            runID: UUID(),
            callID: .init(rawValue: "call"),
            toolID: .init(rawValue: "write"),
            arguments: .object([:]),
        )
        #expect(try await journal.begin(invocation) == nil)
        try await journal.acknowledgeUncertainty(operationID: invocation.operationID)
        let restored = try PortholeAgentJournal(url: workspace.journalURL)
        let history = try await restored.resumeMessages()
        guard case let .tool(results) = try #require(history.last),
              let result = results.first
        else { Issue.record("Expected uncertainty evidence"); return }
        #expect(result.isError)
        #expect(result.output["outcome"] == .string("uncertain"))
        #expect(result.output["message"]?.stringValue?
            .contains("cancellation did not establish rollback") == true)
        await #expect(throws: PortholeAgentError.operationUnresolved(invocation.operationID)) {
            try await restored.begin(invocation)
        }
        try await restored
            .prepare(messages: history + [.user(text: "Inspect the current state first.")])
    }

    @Test func recordsExplicitProviderAndModelForEachRun() async throws {
        let workspace = try AgentTestWorkspace()
        let journal = try PortholeAgentJournal(url: workspace.journalURL)
        let model = PortholeAgentModelIdentity(provider: .anthropic, modelID: "chosen-model")
        let runID = UUID()
        try await journal.recordRun(runID: runID, model: model)
        let restored = try PortholeAgentJournal(url: workspace.journalURL)
        let run = try #require(await restored.snapshot().runs.first)
        #expect(run.runID == runID)
        #expect(run.model == model)
    }

    @Test func rejectsIncompleteImportedToolHistoryBeforeSDKReplay() async throws {
        let workspace = try AgentTestWorkspace()
        let journal = try PortholeAgentJournal(url: workspace.journalURL)
        let invocation = PortholeAgentInvocation(
            operationID: UUID(),
            callID: .init(rawValue: "unfinished"),
            toolID: .init(rawValue: "inspect"),
            arguments: .object([:]),
        )
        await #expect(throws: PortholeAgentError.operationUnresolved(invocation.operationID)) {
            try await journal.prepare(messages: [.assistant(text: "", toolCalls: [invocation])])
        }
    }

    @Test func interruptedExecutionNeedsExplicitReconciliation() async throws {
        let workspace = try AgentTestWorkspace()
        let journal = try PortholeAgentJournal(url: workspace.journalURL)
        let invocation = try await journal.register(
            runID: UUID(),
            callID: .init(rawValue: "call"),
            toolID: .init(rawValue: "inspect"),
            arguments: .object([:]),
        )
        #expect(try await journal.begin(invocation) == nil)
        let restored = try PortholeAgentJournal(url: workspace.journalURL)
        await #expect(throws: PortholeAgentError.operationUnresolved(invocation.operationID)) {
            try await restored.resumeMessages()
        }
        let result = PortholeAgentToolResult(
            callID: invocation.callID,
            toolID: invocation.toolID,
            output: .string("Applied once"),
            isError: false,
        )
        try await restored.reconcile(operationID: invocation.operationID, result: result)
        #expect(try await restored.begin(invocation) == result)
        #expect(try await restored.resumeMessages() == [
            .assistant(text: "", toolCalls: [invocation]),
            .tool(results: [result]),
        ])
    }

    @Test func callIdentityCannotChangeArguments() async throws {
        let workspace = try AgentTestWorkspace()
        let journal = try PortholeAgentJournal(url: workspace.journalURL)
        let runID = UUID()
        _ = try await journal.register(
            runID: runID,
            callID: .init(rawValue: "call"),
            toolID: .init(rawValue: "inspect"),
            arguments: .integer(1),
        )
        await #expect(throws: PortholeAgentError.operationMismatch) {
            try await journal.register(
                runID: runID,
                callID: .init(rawValue: "call"),
                toolID: .init(rawValue: "inspect"),
                arguments: .integer(2),
            )
        }
    }
}

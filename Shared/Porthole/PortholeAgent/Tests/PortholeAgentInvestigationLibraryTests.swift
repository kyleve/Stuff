import Foundation
@testable import PortholeAgent
import PortholeCore
import Testing

struct PortholeAgentInvestigationLibraryTests {
    @Test func keepsOriginalCaptureWhenRestoredFromAnotherScreen() async throws {
        let workspace = try AgentTestWorkspace()
        let firstOrigin = origin(title: "Flight issue")
        let nextOrigin = origin(title: "Border drift")
        let library = try PortholeAgentInvestigationLibrary(anchorURL: workspace.journalURL)
        let first = try library.selectedOrCreate(origin: firstOrigin)
        let journal = try library.journal(for: first)
        #expect(try library.journal(for: first) === journal)
        try await journal.prepare(messages: [.user(text: "Why was this rejected?")])
        let restored = try PortholeAgentInvestigationLibrary(anchorURL: workspace.journalURL)
        let selected = try restored.selectedOrCreate(origin: nextOrigin)
        #expect(selected == first)
        let restoredJournal = try restored.journal(for: selected)
        #expect(restoredJournal.originalOrigin == firstOrigin)
        #expect(try await restoredJournal
            .resumeMessages() == [.user(text: "Why was this rejected?")])
    }

    @Test func newInvestigationCannotOverwriteEarlierEvidence() async throws {
        let workspace = try AgentTestWorkspace()
        let library = try PortholeAgentInvestigationLibrary(anchorURL: workspace.journalURL)
        let first = try library.create(origin: origin(title: "First screen"))
        let firstJournal = try library.journal(for: first)
        let second = try library.create(origin: origin(title: "Second screen"))
        let secondJournal = try library.journal(for: second)
        try await firstJournal.append(messages: [.assistant(text: "Late result", toolCalls: [])])
        #expect(try await secondJournal.resumeMessages().isEmpty)
        #expect(firstJournal.originalOrigin == first.origin)
        try library.select(investigationID: first.id)
        #expect(try library.selectedOrCreate(origin: second.origin).id == first.id)
        #expect(try await firstJournal.resumeMessages() == [.assistant(
            text: "Late result",
            toolCalls: [],
        )])
    }

    private func origin(title: String) -> PortholeAgentOrigin {
        .screen(context: PortholeContext(
            id: .init(rawValue: UUID().uuidString),
            title: title,
            scope: PortholeScopeToken(id: .init(rawValue: "test"), generation: UUID()),
            capturedAt: Date(),
            values: .object(["evidence": .string(title)]),
            objects: [],
            links: [],
            source: nil,
        ))
    }
}

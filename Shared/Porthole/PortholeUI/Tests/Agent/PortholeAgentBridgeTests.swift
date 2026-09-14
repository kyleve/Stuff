import Foundation
@testable import PortholeAgent
import PortholeRuntime
@testable import PortholeUI
import Testing

@MainActor
struct PortholeAgentBridgeTests {
    @Test func failedSetupPreservesManualExecutionAndRetryDoesNotDiscardInvestigations(
    ) async throws {
        let directory = URL.temporaryDirectory.appending(path: "AgentSetup-\(UUID().uuidString)")
        defer {
            do { try FileManager.default.removeItem(at: directory) }
            catch { Issue.record("Could not remove the isolated agent setup fixture: \(error)") }
        }
        let storageURL = directory.appending(path: "investigation.json")
        let libraryURL = directory.appending(path: "investigation.investigations")
        try FileManager.default.createDirectory(at: libraryURL, withIntermediateDirectories: true)
        let selectionURL = libraryURL.appending(path: "selection.json")
        let unreadableSelection = Data("incomplete investigation index".utf8)
        try unreadableSelection.write(to: selectionURL)
        let registry = PortholeRegistry(journal: .init(url: nil), objectLimit: 20)
        let scope = await registry.createScope(id: .init(rawValue: "app"))
        await registry.setEnabled(true)
        try await PortholeBuiltinCapabilities.install(in: registry, scope: scope)
        let controller = PortholePresentationController(
            registry: registry,
            applicationTitle: "Test",
        )
        controller.present(origin: .application(scope))

        #expect(throws: (any Error).self) {
            try controller.configureAgent(
                storageURL: storageURL,
                keychainService: "test.porthole.\(UUID().uuidString)",
                context: nil,
            )
        }
        #expect(controller.agent == nil)
        #expect(controller.agentConfigurationError != nil)
        controller.dismiss()
        controller.present(origin: .application(scope))
        controller.retryAgentConfiguration()
        #expect(controller.agentConfigurationError != nil)
        #expect(try Data(contentsOf: selectionURL) == unreadableSelection)
        _ = try await controller.execute(PortholeInvocation(
            id: UUID(),
            scope: scope,
            capabilityID: .init(rawValue: "porthole.discover"),
            receiver: nil,
            arguments: .object([
                "query": .string("source"),
                "offset": .integer(0),
                "limit": .integer(1),
            ]),
        ))

        // Repair only this isolated fixture. Product retry must never delete a saved investigation.
        try FileManager.default.removeItem(at: selectionURL)
        controller.retryAgentConfiguration()
        #expect(controller.agent != nil)
        #expect(controller.agentConfigurationError == nil)
        #expect(controller.origin == .application(scope))
    }

    @Test func resumesOriginalSelectionWithinSameLiveScopeAndKeepsOperationIdentity() async throws {
        let registry = PortholeRegistry(journal: .init(url: nil), objectLimit: 20)
        let scope = await registry.createScope(id: .init(rawValue: "app"))
        await registry.setEnabled(true)
        try await PortholeBuiltinCapabilities.install(in: registry, scope: scope)
        let original = context(title: "Original issue", scope: scope)
        let current = context(title: "Other screen", scope: scope)
        let controller = PortholePresentationController(
            registry: registry,
            applicationTitle: "Test",
        )
        controller.present(origin: .screen(current))
        let journal = try PortholeAgentJournal(
            storage: AgentUITestStorage(),
            originalOrigin: .screen(context: original),
        )
        let bridge = PortholeAgentBridge(
            controller: controller,
            origin: .screen(original),
            journal: journal,
        )
        let call = discoverCall()
        _ = try await bridge.execute(call)
        let receipt = try #require(try await registry.operationRecord(for: call.operationID))
        #expect(receipt.invocation.id == call.operationID)
        #expect(receipt.invocation.scope == scope)
        let captured = try await bridge.execute(PortholeAgentInvocation(
            operationID: UUID(),
            callID: .init(rawValue: "context"),
            toolID: .init(rawValue: "context"),
            arguments: .object([:]),
        ))
        #expect(try captured["original"]?.decode(PortholeContext.self) == original)
        #expect(controller.origin == .screen(current))
    }

    @Test func relaunchRequiresExplicitContextAdoptionAndOldPresentationCannotCall() async throws {
        let registry = PortholeRegistry(journal: .init(url: nil), objectLimit: 20)
        let oldScope = await registry.createScope(id: .init(rawValue: "app"))
        let newScope = await registry.createScope(id: .init(rawValue: "app"))
        await registry.setEnabled(true)
        try await PortholeBuiltinCapabilities.install(in: registry, scope: newScope)
        let controller = PortholePresentationController(
            registry: registry,
            applicationTitle: "Test",
        )
        controller.present(origin: .application(newScope))
        let journal = try PortholeAgentJournal(
            storage: AgentUITestStorage(),
            originalOrigin: .application(scope: oldScope),
        )
        let bridge = PortholeAgentBridge(
            controller: controller,
            origin: .application(oldScope),
            journal: journal,
        )
        await #expect(throws: PortholeError.staleScope) { try await bridge.execute(discoverCall()) }
        try await journal.continueWithContext(
            .application(scope: newScope),
            provenance: .object(["build": .string("new")]),
        )
        _ = try await bridge.execute(discoverCall())
        #expect(journal.originalOrigin == .application(scope: oldScope))
        controller.dismiss()
        controller.present(origin: .application(newScope))
        await #expect(throws: PortholeError.staleScope) { try await bridge.execute(discoverCall()) }
    }

    private func discoverCall() -> PortholeAgentInvocation {
        PortholeAgentInvocation(
            operationID: UUID(),
            callID: .init(rawValue: UUID().uuidString),
            toolID: .init(rawValue: "discover"),
            arguments: .object([
                "query": .string("source"),
                "offset": .integer(0),
                "limit": .integer(5),
            ]),
        )
    }

    private func context(title: String, scope: PortholeScopeToken) -> PortholeContext {
        PortholeContext(
            id: .init(rawValue: UUID().uuidString),
            title: title,
            scope: scope,
            capturedAt: Date(),
            values: .object([:]),
            objects: [],
            links: [],
            source: nil,
        )
    }
}

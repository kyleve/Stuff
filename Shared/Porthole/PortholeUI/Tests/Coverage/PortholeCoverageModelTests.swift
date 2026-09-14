import Foundation
import PortholeCore
@testable import PortholeUI
import Testing

@MainActor
struct PortholeCoverageModelTests {
    @Test func cancelledDetachedCoverageReadCannotResetTheReattachedPage() async throws {
        let scope = PortholeCoverageSnapshotServices.scope
        let reply = try PortholeValue.encoding(PortholeCoverageModulePage(
            scope: scope,
            total: 0,
            items: [],
        ))
        let executor = PortholeCoverageUITestExecutor(replies: [.suspend, .value(reply)])
        let model = PortholeCoverageModel(scope: scope, module: nil, execute: executor.invoke)
        let detached = Task { await model.loadIfNeeded() }
        defer { executor.finish(.null) }
        try await executor.waitForSuspendedRead()
        detached.cancel()
        model.cancel()
        await model.loadIfNeeded()
        executor.finish(reply)
        await detached.value
        guard case .loaded(.modules) = model.state
        else { Issue.record("Old task cancellation reset the reattached coverage page"); return
        }
        #expect(executor.invocations.count == 2)
    }

    @Test func rehostingPreservesCompletedPagesAndQueryChangesInvalidateThem() async throws {
        let scope = PortholeCoverageSnapshotServices.scope
        let executor = try PortholeCoverageUITestExecutor(replies: [
            .value(.encoding(PortholeCoverageModulePage(scope: scope, total: 0, items: []))),
            .value(.encoding(PortholeCoveragePage(scope: scope, total: 0, items: []))),
        ])
        let model = PortholeCoverageModel(scope: scope, module: nil, execute: executor.invoke)
        await model.loadIfNeeded()
        model.cancel()
        await model.loadIfNeeded()
        guard case .loaded(.modules) = model.state
        else { Issue.record("Rehosting discarded the module page"); return }
        #expect(executor.invocations.count == 1)
        model.search = "inactive"
        model.cancel()
        await model.loadIfNeeded()
        guard case .loaded(.declarations) = model.state
        else { Issue.record("Changed query reused an old page"); return }
        #expect(executor.invocations.count == 2)
        model.search = "inactive"
        await model.loadIfNeeded()
        #expect(executor.invocations.count == 2)
    }

    @Test func queryChangedBeforeFirstAttachmentIsTheRequestThatLoads() async throws {
        let scope = PortholeCoverageSnapshotServices.scope
        let executor = try PortholeCoverageUITestExecutor(replies: [
            .value(.encoding(PortholeCoveragePage(scope: scope, total: 0, items: []))),
        ])
        let model = PortholeCoverageModel(scope: scope, module: nil, execute: executor.invoke)
        model.search = "unsupported"
        model.cancel()
        await model.loadIfNeeded()
        let invocation = try #require(executor.invocations.first)
        #expect(invocation.capabilityID == PortholeCoverageCapabilities.declarations)
        guard case let .object(arguments) = invocation.arguments
        else { Issue.record("Expected a query"); return }
        let query = try #require(arguments["query"]).decode(PortholeCoverageQuery.self)
        #expect(query.search == "unsupported")
    }

    @Test func includesModulesWithoutActiveBindingsThroughTheSharedRead() async {
        let executor = PortholeCoverageSnapshotServices()
        let model = PortholeCoverageModel(
            scope: PortholeCoverageSnapshotServices.scope,
            module: nil,
            execute: executor.invoke,
        )
        await model.load()
        guard case let .loaded(.modules(page)) = model.state
        else { Issue.record("Expected module page"); return }
        #expect(page.items
            .contains {
                $0.module.rawValue == "PlatformDiagnostics" && $0.counts.callable == 0 && $0.counts
                    .inactive == 2
            })
        #expect(page.items.contains { $0.counts.total == 0 })
    }

    @Test func paginatesOneBoundedPageAndResetsSearchOffset() async throws {
        let scope = PortholeCoverageSnapshotServices.scope
        let entries = (0 ..< 50).map { index in
            let original = PortholeCoverageSnapshotServices.entries[0]
            let declaration = original.declaration
            return PortholeCoverageEntry(
                module: original.module,
                declaration: .init(
                    id: .init(rawValue: "Example.sample\(index)"),
                    name: declaration.name,
                    kind: declaration.kind,
                    signature: declaration.signature,
                    source: declaration.source,
                    sourceSHA256: declaration.sourceSHA256,
                    conditions: [],
                    plannedAvailability: .callable,
                    origin: .generated,
                ),
                state: .callable,
                installedCapabilityID: nil,
            )
        }
        let executor = try PortholeCoverageUITestExecutor(replies: [
            .value(.encoding(PortholeCoveragePage(scope: scope, total: 51, items: entries))),
            .value(.encoding(PortholeCoveragePage(scope: scope, total: 51, items: [entries[0]]))),
        ])
        let model = PortholeCoverageModel(
            scope: scope,
            module: .init(rawValue: "Example"),
            execute: executor.invoke,
        )
        await model.load()
        model.nextPage()
        #expect(model.offset == 50)
        model.cancel()
        await model.loadIfNeeded()
        guard case let .loaded(.declarations(page)) = model.state
        else { Issue.record("Expected declarations"); return }
        #expect(page.items.count == 1)
        #expect(executor.invocations
            .allSatisfy {
                $0.capabilityID == PortholeCoverageCapabilities.declarations && $0.scope == scope
            })
        let last = try #require(executor.invocations.last)
        guard case let .object(arguments) = last.arguments
        else { Issue.record("Expected query"); return }
        let query = try #require(arguments["query"]).decode(PortholeCoverageQuery.self)
        #expect(query.offset == 50 && query.limit == 50 && query.status == .all)
        model.nextPage()
        #expect(model.offset == 50)
        model.search = "Unbound generic"
        #expect(model.offset == 0)
        #expect(model.request.search == "Unbound generic")
    }

    @Test func delayedReadCannotReplaceANewerSearch() async throws {
        let scope = PortholeCoverageSnapshotServices.scope
        let executor = try PortholeCoverageUITestExecutor(replies: [
            .suspend,
            .value(.encoding(PortholeCoveragePage(scope: scope, total: 0, items: []))),
        ])
        let model = PortholeCoverageModel(scope: scope, module: nil, execute: executor.invoke)
        let pending = Task { await model.load() }
        defer { executor.finish(.null) }
        try await executor.waitForSuspendedRead()
        model.search = "missing signature"
        model.cancel()
        await model.loadIfNeeded()
        try executor.finish(.encoding(PortholeCoverageModulePage(
            scope: scope,
            total: 0,
            items: [],
        )))
        await pending.value
        guard case .loaded(.declarations) = model.state
        else { Issue.record("Old module page replaced the search"); return }
    }

    @Test func cancellationRejectsDelayedSuccessAndFailureRemainsRetryable() async throws {
        let scope = PortholeCoverageSnapshotServices.scope
        let executor = try PortholeCoverageUITestExecutor(replies: [
            .suspend,
            .fail,
            .value(.encoding(PortholeCoverageModulePage(scope: scope, total: 0, items: []))),
        ])
        let model = PortholeCoverageModel(scope: scope, module: nil, execute: executor.invoke)
        let pending = Task { await model.load() }
        defer { executor.finish(.null) }
        try await executor.waitForSuspendedRead()
        model.cancel()
        try executor.finish(.encoding(PortholeCoverageModulePage(
            scope: scope,
            total: 0,
            items: [],
        )))
        await pending.value
        guard case .idle = model.state
        else { Issue.record("Cancelled read became visible"); return }
        await model.load()
        guard case let .failed(message) = model.state
        else { Issue.record("Failure looked successful"); return }
        #expect(message.contains("Coverage source is unavailable"))
        await model.load()
        guard case .loaded(.modules) = model.state else { Issue.record("Retry failed"); return }
    }
}

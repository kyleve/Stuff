import Foundation
import PortholeRuntime
@_spi(Testing) @testable import PortholeUI
import Testing

@MainActor
struct PortholePresentationControllerTests {
    @Test func cancelledAttachmentAndReplacementJoinTheSameSuspendedRefresh() async throws {
        let registry = PortholeRegistry(journal: .init(url: nil), objectLimit: 10)
        let scope = await registry.createScope(id: .init(rawValue: "reattached"))
        await registry.setEnabled(true)
        let controller = PortholePresentationController(
            registry: registry,
            applicationTitle: "Fixture",
        )
        let gate = PortholeScopeRefreshTestGate()
        defer { gate.release(); controller.dismiss() }
        controller.beforeNextScopeRefresh { await gate.suspend() }
        controller.present(origin: .application(scope))
        let detached = Task { await controller.refreshIfNeeded() }
        try #require(await PortholeScopeRefreshTestGate.waitUntil { gate.isSuspended })
        detached.cancel()
        let reattached = Task { await controller.refreshIfNeeded() }
        try #require(await PortholeScopeRefreshTestGate
            .waitUntil { controller.scopeRefreshWaiterCount == 2 })
        gate.release()
        await detached.value
        await reattached.value
        guard case .loaded = controller.loadState
        else { Issue.record("Cancelled attachment left the replacement idle"); return }
        #expect(controller.scopeRefreshWaiterCount == 0)
    }

    @Test func alreadyCancelledAttachmentDoesNotStartOrSuppressTheNextRefresh() async throws {
        let registry = PortholeRegistry(journal: .init(url: nil), objectLimit: 10)
        let scope = await registry.createScope(id: .init(rawValue: "cancelled"))
        await registry.setEnabled(true)
        let controller = PortholePresentationController(
            registry: registry,
            applicationTitle: "Fixture",
        )
        let gate = PortholeScopeRefreshTestGate()
        defer { gate.release(); controller.dismiss() }
        controller.beforeNextScopeRefresh { await gate.suspend() }
        controller.present(origin: .application(scope))
        let cancelled = Task { await controller.refreshIfNeeded() }
        cancelled.cancel()
        await cancelled.value
        #expect(!gate.isSuspended)
        #expect(controller.scopeRefreshWaiterCount == 0)
        guard case .idle = controller.loadState
        else { Issue.record("Cancelled attachment initiated a read"); return }
        let active = Task { await controller.refreshIfNeeded() }
        try #require(await PortholeScopeRefreshTestGate.waitUntil { gate.isSuspended })
        gate.release()
        await active.value
        guard case .loaded = controller.loadState
        else { Issue.record("Cancelled attachment suppressed the next read"); return }
    }

    @Test func dismissedRefreshCannotChangeAReplacementPresentationAfterItResumes() async throws {
        let registry = PortholeRegistry(journal: .init(url: nil), objectLimit: 10)
        let firstScope = await registry.createScope(id: .init(rawValue: "old"))
        await registry.setEnabled(true)
        let controller = PortholePresentationController(
            registry: registry,
            applicationTitle: "Fixture",
        )
        let gate = PortholeScopeRefreshTestGate()
        defer { gate.release(); controller.dismiss() }
        controller.beforeNextScopeRefresh { await gate.suspend() }
        controller.present(origin: .application(firstScope))
        let old = Task { await controller.refreshIfNeeded() }
        try #require(await PortholeScopeRefreshTestGate.waitUntil { gate.isSuspended })
        controller.dismiss()
        let replacement = await registry.createScope(id: firstScope.id)
        let source = PortholeSourceFile(path: "New.swift", content: "struct Replacement {}")
        try await registry.installSourceArchive(
            String(decoding: JSONEncoder().encode([source]), as: UTF8.self),
            in: replacement,
        )
        controller.present(origin: .application(replacement))
        await controller.refreshIfNeeded()
        gate.release()
        await old.value
        guard case let .loaded(snapshot) = controller.loadState
        else { Issue.record("Old cancellation erased the replacement load"); return }
        #expect(snapshot.sources == [source])
        #expect(controller.origin?.scope == replacement)
    }

    @Test func explicitRefreshSupersedesTheSuspendedOperationWithinTheSamePresentation(
    ) async throws {
        let registry = PortholeRegistry(journal: .init(url: nil), objectLimit: 10)
        let scope = await registry.createScope(id: .init(rawValue: "same-presentation"))
        await registry.setEnabled(true)
        let controller = PortholePresentationController(
            registry: registry,
            applicationTitle: "Fixture",
        )
        let gate = PortholeScopeRefreshTestGate()
        defer { gate.release(); controller.dismiss() }
        controller.beforeNextScopeRefresh { await gate.suspend() }
        controller.present(origin: .application(scope))
        let old = Task { await controller.refreshIfNeeded() }
        try #require(await PortholeScopeRefreshTestGate.waitUntil { gate.isSuspended })
        let session = controller.sessionID
        await controller.refresh()
        gate.release()
        await old.value
        guard case .loaded = controller.loadState
        else { Issue.record("Old cancellation erased explicit refresh results"); return }
        #expect(controller.sessionID == session)
    }

    @Test func initialLoadSurvivesRehostingButExplicitRefreshAndNewSessionsReadAgain() async {
        let registry = PortholeRegistry(journal: .init(url: nil), objectLimit: 10)
        let scope = await registry.createScope(id: .init(rawValue: "preview"))
        await registry.setEnabled(true)
        let controller = PortholePresentationController(
            registry: registry,
            applicationTitle: "Fixture",
        )
        controller.present(origin: .application(scope))
        await controller.refreshIfNeeded()
        guard case .loaded = controller.loadState
        else { Issue.record("Initial load failed"); return }
        await registry.setEnabled(false)
        await controller.refreshIfNeeded()
        guard case .loaded = controller.loadState
        else { Issue.record("Rehosting restarted a completed load"); return }
        await controller.refresh()
        guard case .failed = controller.loadState
        else { Issue.record("Explicit refresh did not check the disabled runtime"); return }
        await registry.setEnabled(true)
        await controller.refreshIfNeeded()
        guard case .failed = controller.loadState
        else { Issue.record("Rehosting retried a failed load"); return }
        await controller.refresh()
        guard case .loaded = controller.loadState
        else { Issue.record("Explicit retry did not reload"); return }
        controller.dismiss()
        await registry.setEnabled(false)
        controller.present(origin: .application(scope))
        await controller.refreshIfNeeded()
        guard case .failed = controller.loadState
        else { Issue.record("New presentation reused old results"); return }
        controller.dismiss()
    }

    @Test func nativePresentationObserversSeeFinalSessionStateAndDoNotRetainTheirOwner(
    ) async throws {
        let registry = PortholeRegistry(journal: .init(url: nil), objectLimit: 20)
        let scope = await registry.createScope(id: .init(rawValue: "test"))
        let controller = PortholePresentationController(
            registry: registry,
            applicationTitle: "Fixture",
        )
        var sessions: [UUID?] = []
        var observer: PortholePresentationObserverTestProbe? = .init {
            sessions.append(controller.sessionID)
        }
        weak let weakObserver = observer
        try controller.registerPresentationObserver(#require(observer))
        controller.present(origin: .application(scope))
        let firstSession = try #require(controller.sessionID)
        #expect(sessions == [firstSession])
        controller.present(origin: .application(scope))
        #expect(sessions == [firstSession])
        controller.dismiss()
        #expect(sessions == [firstSession, nil])
        controller.dismiss()
        #expect(sessions == [firstSession, nil])

        try controller.unregisterPresentationObserver(#require(observer))
        controller.present(origin: .application(scope))
        controller.dismiss()
        #expect(sessions == [firstSession, nil])
        try controller.registerPresentationObserver(#require(observer))
        observer = nil
        #expect(weakObserver == nil)
        controller.present(origin: .application(scope))
        controller.dismiss()
        #expect(sessions == [firstSession, nil])
    }

    @Test func dismissStopsObservationsBeforeTheInvocationViewDisappears() async throws {
        let registry = PortholeRegistry(journal: .init(url: nil), objectLimit: 20)
        let scope = await registry.createScope(id: .init(rawValue: "test"))
        let controller = PortholePresentationController(
            registry: registry,
            applicationTitle: "Fixture",
        )
        controller.present(origin: .application(scope))
        let executor = PortholeObservationUITestExecutor()
        defer { executor.finishPendingCalls() }
        let observation = PortholeObservationModel()
        controller.registerObservation(observation)
        observation.start(
            invocation: PortholeObservationUITestSupport.invocation(scope: scope),
            execute: executor.execute,
        )
        #expect(await PortholeObservationUITestSupport.waitUntil { executor.reads.count == 1 })
        let reference = try #require(executor.reads.first?.observation)
        controller.dismiss()
        #expect(!observation.canStop)
        #expect(await PortholeObservationUITestSupport.waitUntil { !observation.isActive })
        #expect(executor.stops == [reference])
        #expect(!controller.isPresented)
    }

    @Test func disabledCompositionDoesNotCreateStorageOrOptionalSubsystems() async {
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        let journal = PortholeOperationJournal(url: directory.appending(path: "operations.json"))
        let registry = PortholeRegistry(journal: journal, objectLimit: 20)
        let controller = PortholePresentationController(
            registry: registry,
            applicationTitle: "Fixture",
        )
        controller.console.run(using: controller)
        controller.dismiss()
        #expect(await !registry.isEnabled())
        #expect(!controller.isPresented)
        #expect(controller.agent == nil)
        #expect(controller.github == nil)
        #expect(controller.host == nil)
        #expect(!controller.console.isRunning)
        #expect(!FileManager.default.fileExists(atPath: directory.path))
    }

    @Test func reviewIncludesRemoteRequestsWithoutLocalContinuations() async throws {
        let registry = PortholeRegistry(journal: .init(url: nil), objectLimit: 20)
        let scope = await registry.createScope(id: .init(rawValue: "test"))
        await registry.setEnabled(true)
        let capability = capability()
        try await registry.register(capability, in: scope) { _, _ in .integer(9) }
        let controller = PortholePresentationController(
            registry: registry,
            applicationTitle: "Fixture",
        )
        controller.present(origin: .application(scope))
        let invocation = PortholeInvocation(
            id: UUID(),
            scope: scope,
            capabilityID: capability.id,
            receiver: nil,
            arguments: .object([:]),
        )
        do {
            _ = try await registry.invoke(invocation)
            Issue.record("A mutation ran without review")
        } catch PortholeError.approvalRequired {}
        await controller.refreshApprovals()
        let proposal = try #require(controller.pendingApprovals.first)
        #expect(proposal.invocation == invocation)
        await controller.approve(proposal)
        #expect(try await registry.invoke(invocation) == .integer(9))
    }

    @Test func presentationFreezesScreenOriginWhileNavigationChanges() async {
        let registry = PortholeRegistry(journal: .init(url: nil), objectLimit: 20)
        let scope = await registry.createScope(id: .init(rawValue: "test"))
        let first = context("Issue", scope: scope)
        let next = context("Evidence", scope: scope)
        let controller = PortholePresentationController(
            registry: registry,
            applicationTitle: "Fixture",
        )
        controller.present(origin: .screen(first))
        controller.registerContexts([next])
        controller.navigate(to: next)
        controller.present(origin: .screen(next))
        #expect(controller.origin == .screen(first))
        #expect(controller.selectedContext == next)
        controller.navigate(to: first)
        #expect(controller.breadcrumbs.count == 1)
        controller.dismiss()
        #expect(!controller.isPresented)
    }

    @Test func approvalResumesTheExactInvocationOnce() async throws {
        let registry = PortholeRegistry(journal: .init(url: nil), objectLimit: 20)
        let scope = await registry.createScope(id: .init(rawValue: "test"))
        await registry.setEnabled(true)
        let capability = capability()
        let counter = Counter()
        try await registry.register(capability, in: scope) { _, _ in await counter.increment() }
        let controller = PortholePresentationController(
            registry: registry,
            applicationTitle: "Fixture",
        )
        controller.present(origin: .application(scope))
        let invocation = PortholeInvocation(
            id: UUID(),
            scope: scope,
            capabilityID: capability.id,
            receiver: nil,
            arguments: .object([:]),
        )
        let operation = Task { try await controller.execute(invocation) }
        let deadline = ContinuousClock.now.advanced(by: .seconds(2))
        while controller.pendingApprovals.isEmpty,
              ContinuousClock.now < deadline
        {
            await Task.yield()
        }
        let proposal = try #require(controller.pendingApprovals.first)
        #expect(proposal.invocation == invocation)
        #expect(await counter.value == 0)
        await controller.approve(proposal)
        #expect(try await operation.value == .integer(1))
        #expect(try await controller.execute(invocation) == .integer(1))
        #expect(await counter.value == 1)
    }

    @Test func dismissRejectsPendingApproval() async throws {
        let registry = PortholeRegistry(journal: .init(url: nil), objectLimit: 20)
        let scope = await registry.createScope(id: .init(rawValue: "test"))
        await registry.setEnabled(true)
        let capability = capability()
        try await registry.register(capability, in: scope) { _, _ in .integer(1) }
        let controller = PortholePresentationController(
            registry: registry,
            applicationTitle: "Fixture",
        )
        controller.present(origin: .application(scope))
        let invocation = PortholeInvocation(
            id: UUID(),
            scope: scope,
            capabilityID: capability.id,
            receiver: nil,
            arguments: .object([:]),
        )
        let operation = Task { try await controller.execute(invocation) }
        let deadline = ContinuousClock.now.advanced(by: .seconds(2))
        while controller.pendingApprovals.isEmpty,
              ContinuousClock.now < deadline
        {
            await Task.yield()
        }
        #expect(!controller.pendingApprovals.isEmpty)
        controller.dismiss()
        await #expect(throws: CancellationError.self) { try await operation.value }
        #expect(controller.pendingApprovals.isEmpty)
    }

    private func context(_ name: String, scope: PortholeScopeToken) -> PortholeContext {
        PortholeContext(
            id: .init(rawValue: name),
            title: name,
            scope: scope,
            capturedAt: .distantPast,
            values: .object([:]),
            objects: [],
            links: [],
            source: nil,
        )
    }

    private func capability() -> PortholeCapability {
        PortholeCapability(
            id: .init(rawValue: "test.mutation"),
            module: .init(rawValue: "Fixture"),
            name: "Mutation",
            summary: "Test mutation",
            parameters: [],
            result: .integer,
            effect: .mutation,
            source: nil,
            ownership: .adapter,
            availability: .callable,
        )
    }

    private actor Counter {
        private(set) var value = 0
        func increment() -> PortholeValue {
            value += 1; return .integer(Int64(value))
        }
    }
}

import Foundation
@_spi(Testing) import PortholeRuntime
import Testing

struct PortholeRegistryTests {
    @Test func nativeArgumentsRemainLeasedAcrossSuspension() async throws {
        let registry = await PortholeRuntimeTestSupport.makeRegistry()
        let scope = await registry.createScope(id: .init(rawValue: "app"))
        let pool = PortholeObjectRetention.bounded(
            pool: .init(rawValue: "captures"),
            maximumCount: 1,
        )
        let reference = try await registry.retain("original", in: scope, retention: pool)
        let gate = PortholeTestGate()
        try await registry.register(
            PortholeRuntimeTestSupport.capability(effect: .read),
            in: scope,
        ) { invocation, registry in
            await gate.enter()
            return try await .string(registry.resolve(
                invocation.receiver,
                as: String.self,
                in: invocation.scope,
            ))
        }
        let invocation = PortholeInvocation(
            id: UUID(),
            scope: scope,
            capabilityID: .init(rawValue: "test.operation"),
            receiver: reference,
            arguments: .object([:]),
        )
        let task = Task { try await registry.invoke(invocation) }
        await gate.waitForArrival()
        await #expect(throws: PortholeError.capacityExceeded) { try await registry.retain(
            "replacement",
            in: scope,
            retention: pool,
        ) }
        await #expect(throws: PortholeError.operationInProgress) {
            try await registry.release(reference)
        }
        await gate.release()
        #expect(try await task.value == .string("original"))
        _ = try await registry.retain("replacement", in: scope, retention: pool)
        await #expect(throws: PortholeError.unknownObject) { try await registry.resolve(
            reference,
            as: String.self,
            in: scope,
        ) }
    }

    @Test func objectsCreatedDuringNativeWorkStayLeasedUntilDelivery() async throws {
        let registry = await PortholeRuntimeTestSupport.makeRegistry()
        let scope = await registry.createScope(id: .init(rawValue: "app"))
        let pool = PortholeObjectRetention.bounded(
            pool: .init(rawValue: "results"),
            maximumCount: 1,
        )
        let gate = PortholeTestGate()
        try await registry.register(
            PortholeRuntimeTestSupport.capability(effect: .read),
            in: scope,
        ) { invocation, registry in
            let reference = try await registry.retain(
                "in flight",
                in: invocation.scope,
                retention: pool,
            )
            await gate.enter()
            return try .object(["$reference": .encoding(reference)])
        }
        let task = Task {
            try await registry.invoke(PortholeRuntimeTestSupport.invocation(scope: scope))
        }
        await gate.waitForArrival()
        await #expect(throws: PortholeError.capacityExceeded) { try await registry.retain(
            "replacement",
            in: scope,
            retention: pool,
        ) }
        await gate.release()
        let result = try await task.value
        let reference = try #require(result["$reference"]).decode(PortholeObjectReference.self)
        #expect(try await registry.resolve(reference, as: String.self, in: scope) == "in flight")
        _ = try await registry.retain("replacement", in: scope, retention: pool)
        await #expect(throws: PortholeError.unknownObject) { try await registry.resolve(
            reference,
            as: String.self,
            in: scope,
        ) }
    }

    @Test(arguments: [PortholeEffect.read, .mutation])
    func completedReceiptsKeepExpiredResultIdentityWithoutRepeatingWork(
        effect: PortholeEffect,
    ) async throws {
        let journalURL = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString).appending(path: "operations.json")
        let journal = PortholeOperationJournal(url: journalURL)
        let registry = PortholeRegistry(journal: journal, objectLimit: 20)
        await registry.setEnabled(true)
        let scope = await registry.createScope(id: .init(rawValue: "app"))
        let pool = PortholeObjectRetention.bounded(
            pool: .init(rawValue: "results"),
            maximumCount: 1,
        )
        let counter = PortholeTestCounter()
        try await registry.register(
            PortholeRuntimeTestSupport.capability(effect: effect),
            in: scope,
        ) { invocation, registry in
            let count = await counter.increment()
            let reference = try await registry.retain(count, in: invocation.scope, retention: pool)
            return try .object(["$reference": .encoding(reference)])
        }
        let invocation = PortholeRuntimeTestSupport.invocation(scope: scope)
        if effect.requiresApproval {
            await #expect(throws: PortholeError.self) { try await registry.invoke(invocation) }
            try await registry.approve(#require(await registry.pendingApprovals().first))
        }
        let original = try await registry.invoke(invocation)
        let reference = try #require(original["$reference"]).decode(PortholeObjectReference.self)
        let replacement = try await registry.retain(2, in: scope, retention: pool)
        #expect(replacement != reference)
        #expect(try await registry.invoke(invocation) == original)
        #expect(try await registry.operationRecord(for: invocation.id)?
            .status == .succeeded(original))
        #expect(await counter.count == 1)
        await #expect(throws: PortholeError.unknownObject) {
            try await registry.resolve(reference, as: Int.self, in: scope)
        }
        #expect(try await registry.resolve(replacement, as: Int.self, in: scope) == 2)
        if effect.requiresApproval {
            let restored = PortholeOperationJournal(url: journalURL)
            #expect(try await restored.record(for: invocation.id)?.status == .succeeded(original))
            try FileManager.default.removeItem(at: journalURL.deletingLastPathComponent())
        } else {
            #expect(try await journal.allRecords().isEmpty)
        }
    }

    @Test func readPollingDoesNotPersistHistoryAndRetriesUseOnlyTheBoundedCache() async throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        let journal = PortholeOperationJournal(url: directory.appending(path: "operations.json"))
        let registry = PortholeRegistry(
            journal: journal,
            objectLimit: 20,
            readReceiptLimit: 2,
            readReceiptByteLimit: 4096,
        )
        await registry.setEnabled(true)
        let scope = await registry.createScope(id: .init(rawValue: "reads"))
        let counter = PortholeTestCounter()
        try await registry.register(
            PortholeRuntimeTestSupport.capability(effect: .read),
            in: scope,
        ) { _, _ in
            await .integer(Int64(counter.increment()))
        }
        let original = PortholeRuntimeTestSupport.invocation(scope: scope)
        #expect(try await registry.invoke(original) == .integer(1))
        #expect(try await registry.invoke(original) == .integer(1))
        for _ in 0 ..<
            10
        {
            _ = try await registry.invoke(PortholeRuntimeTestSupport.invocation(scope: scope))
        }
        #expect(try await registry.operationRecord(for: original.id) == nil)
        #expect(try await registry.invoke(original) == .integer(12))
        #expect(try await journal.allRecords().isEmpty)
        #expect(!FileManager.default.fileExists(atPath: directory.path))
        await registry.setEnabled(false)
        #expect(try await registry.operationRecord(for: original.id) == nil)
    }

    @Test(arguments: [PortholeEffect.mutation, .unknown, .isolated])
    func readCachePressureNeverEvictsDurableSideEffectReceipts(effect: PortholeEffect) async throws {
        let journal = PortholeOperationJournal(url: nil)
        let registry = PortholeRegistry(
            journal: journal,
            objectLimit: 20,
            readReceiptLimit: 1,
            readReceiptByteLimit: 4096,
        )
        await registry.setEnabled(true)
        let scope = await registry.createScope(id: .init(rawValue: "effects"))
        let counter = PortholeTestCounter()
        try await registry.register(
            PortholeRuntimeTestSupport.capability(effect: effect),
            in: scope,
        ) { _, _ in
            await .integer(Int64(counter.increment()))
        }
        let invocation = PortholeRuntimeTestSupport.invocation(scope: scope)
        if effect.requiresApproval {
            await #expect(throws: PortholeError.self) { try await registry.invoke(invocation) }
            try await registry.approve(#require(await registry.pendingApprovals().first))
        }
        #expect(try await registry.invoke(invocation) == .integer(1))
        let readScope = await registry.createScope(id: .init(rawValue: "reads"))
        try await registry.register(
            PortholeRuntimeTestSupport.capability(effect: .read),
            in: readScope,
        ) { _, _ in .null }
        for _ in 0 ..<
            10
        {
            _ = try await registry.invoke(PortholeRuntimeTestSupport.invocation(scope: readScope))
        }
        #expect(try await journal.allRecords().count == 1)
        #expect(try await registry.invoke(invocation) == .integer(1))
        #expect(await counter.count == 1)
    }

    @Test func durableReceiptTakesPrecedenceOverAnInMemoryReadReceipt() async throws {
        let journal = PortholeOperationJournal(url: nil)
        let registry = PortholeRegistry(journal: journal, objectLimit: 20)
        await registry.setEnabled(true)
        let scope = await registry.createScope(id: .init(rawValue: "reads"))
        try await registry.register(
            PortholeRuntimeTestSupport.capability(effect: .read),
            in: scope,
        ) { _, _ in .integer(1) }
        let invocation = PortholeRuntimeTestSupport.invocation(scope: scope)
        #expect(try await registry.invoke(invocation) == .integer(1))
        try await journal.write(.init(invocation: invocation, status: .succeeded(.integer(2))))
        #expect(try await registry.invoke(invocation) == .integer(2))
    }

    @MainActor @Test func mainActorProtocolHandlesPreserveIsolationTypeAndGeneration() async throws {
        let registry = await PortholeRuntimeTestSupport.makeRegistry()
        let scope = await registry.createScope(id: .init(rawValue: "main-actor"))
        let value: any PortholeActorValue = PortholeActorValueImplementation()
        let encoded = try await registry.encodeMainActor(PortholeMainActorValue(value), in: scope)
        let reference = try #require(encoded["$reference"]).decode(PortholeObjectReference.self)
        #expect(reference.typeName == String(reflecting: (any PortholeActorValue).self))
        let restored = try await registry.decodeMainActor(
            encoded,
            as: PortholeMainActorValue<any PortholeActorValue>.self,
            in: scope,
        )
        restored.value.count += 1
        #expect(value.count == 1)
        await #expect(throws: PortholeError.self) {
            try await registry.resolveMainActor(
                reference,
                as: PortholeMainActorValue<String>.self,
                in: scope,
            )
        }
        let replacement = await registry.createScope(id: scope.id)
        await #expect(throws: PortholeError.unknownObject) {
            try await registry.resolveMainActor(
                reference,
                as: PortholeMainActorValue<any PortholeActorValue>.self,
                in: replacement,
            )
        }
    }

    @Test func mutationRequiresExactApprovalAndExecutesOnlyOnce() async throws {
        let registry = await PortholeRuntimeTestSupport.makeRegistry()
        let scope = await registry.createScope(id: .init(rawValue: "app"))
        let counter = PortholeTestCounter()
        let capability = PortholeRuntimeTestSupport.capability(effect: .mutation)
        try await registry.register(capability, in: scope) { _, _ in
            await .integer(Int64(counter.increment()))
        }
        let invocation = PortholeRuntimeTestSupport.invocation(scope: scope)
        await #expect(throws: PortholeError.self) { try await registry.invoke(invocation) }
        #expect(await counter.count == 0)
        let proposal = try #require(await registry.pendingApprovals().first)
        try await registry.approve(proposal)
        #expect(try await registry.invoke(invocation) == .integer(1))
        #expect(try await registry.invoke(invocation) == .integer(1))
        #expect(await counter.count == 1)
        await #expect(throws: PortholeError.operationConflict) {
            try await registry.approve(proposal)
        }
    }

    @Test func concurrentDuplicateCannotRunTwice() async throws {
        let registry = await PortholeRuntimeTestSupport.makeRegistry()
        let scope = await registry.createScope(id: .init(rawValue: "app"))
        let gate = PortholeTestGate()
        try await registry.register(
            PortholeRuntimeTestSupport.capability(effect: .read),
            in: scope,
        ) { _, _ in
            await gate.enter()
            return .integer(1)
        }
        let invocation = PortholeRuntimeTestSupport.invocation(scope: scope)
        let first = Task { try await registry.invoke(invocation) }
        await gate.waitForArrival()
        await #expect(throws: PortholeError.operationInProgress) {
            try await registry.invoke(invocation)
        }
        await gate.release()
        #expect(try await first.value == .integer(1))
    }

    @Test func scopeReplacementRejectsLateResultsAndOldReferences() async throws {
        let registry = await PortholeRuntimeTestSupport.makeRegistry()
        let scope = await registry.createScope(id: .init(rawValue: "app"))
        let object = try await registry.retain("old", in: scope)
        let gate = PortholeTestGate()
        try await registry.register(
            PortholeRuntimeTestSupport.capability(effect: .read),
            in: scope,
        ) { _, _ in
            await gate.enter()
            return .string("late")
        }
        let invocation = PortholeRuntimeTestSupport.invocation(scope: scope)
        let operation = Task { try await registry.invoke(invocation) }
        await gate.waitForArrival()
        let replacement = await registry.createScope(id: scope.id)
        await gate.release()
        await #expect(throws: PortholeError.staleScope) { try await operation.value }
        #expect(try await registry.operationRecord(for: invocation.id) == nil)
        await #expect(throws: PortholeError.unknownObject) {
            try await registry.resolve(object, as: String.self, in: replacement)
        }
    }

    @Test(arguments: [PortholeEffect.read, .mutation])
    func disableAndReenableRejectsLateDeliveryWithoutLosingCompletedMutations(
        effect: PortholeEffect,
    ) async throws {
        let registry = await PortholeRuntimeTestSupport.makeRegistry()
        let scope = await registry.createScope(id: .init(rawValue: "app"))
        let gate = PortholeTestGate()
        try await registry.register(
            PortholeRuntimeTestSupport.capability(effect: effect),
            in: scope,
        ) { _, _ in
            await gate.enter()
            return .integer(1)
        }
        let invocation = PortholeRuntimeTestSupport.invocation(scope: scope)
        if effect.requiresApproval {
            await #expect(throws: PortholeError.self) { try await registry.invoke(invocation) }
            let proposal = try #require(await registry.pendingApprovals().first)
            try await registry.approve(proposal)
        }
        let operation = Task { try await registry.invoke(invocation) }
        await gate.waitForArrival()
        await registry.setEnabled(false)
        await registry.setEnabled(true)
        await gate.release()
        await #expect(throws: CancellationError.self) { try await operation.value }
        let receipt = try await registry.operationRecord(for: invocation.id)
        if effect == .read {
            #expect(receipt == nil)
        } else {
            #expect(receipt?.status == .succeeded(.integer(1)))
            #expect(try await registry.invoke(invocation) == .integer(1))
        }
    }

    @Test(arguments: [PortholeEffect.read, .mutation], [false, true])
    func disableAndReenableRejectsSuspendedJournalLookup(
        effect: PortholeEffect,
        hasReceipt: Bool,
    ) async throws {
        let journal = PortholeOperationJournal(url: nil)
        let registry = PortholeRegistry(journal: journal, objectLimit: 20)
        await registry.setEnabled(true)
        let scope = await registry.createScope(id: .init(rawValue: "app"))
        let counter = PortholeTestCounter()
        try await registry.register(
            PortholeRuntimeTestSupport.capability(effect: effect),
            in: scope,
        ) { _, _ in
            await .integer(Int64(counter.increment()))
        }
        let invocation = PortholeRuntimeTestSupport.invocation(scope: scope)
        if effect.requiresApproval {
            await #expect(throws: PortholeError.self) { try await registry.invoke(invocation) }
            let proposal = try #require(await registry.pendingApprovals().first)
            try await registry.approve(proposal)
        }
        if hasReceipt {
            #expect(try await registry.invoke(invocation) == .integer(1))
        }
        let gate = PortholeTestGate()
        await journal.setLookupBarrier { await gate.enter() }
        let operation = Task { try await registry.invoke(invocation) }
        await gate.waitForArrival()
        await registry.setEnabled(false)
        await registry.setEnabled(true)
        await journal.setLookupBarrier(nil)
        await gate.release()
        await #expect(throws: CancellationError.self) { try await operation.value }
        #expect(await counter.count == (hasReceipt ? 1 : 0))
        #expect(await registry.pendingApprovals().isEmpty)
    }

    @Test func unknownEffectFailureCannotBeRetried() async throws {
        let registry = await PortholeRuntimeTestSupport.makeRegistry()
        let scope = await registry.createScope(id: .init(rawValue: "app"))
        let counter = PortholeTestCounter()
        try await registry.register(
            PortholeRuntimeTestSupport.capability(effect: .unknown),
            in: scope,
        ) { _, _ in
            _ = await counter.increment()
            throw PortholeError.unsupported("Injected interruption")
        }
        let invocation = PortholeRuntimeTestSupport.invocation(scope: scope)
        await #expect(throws: PortholeError.self) { try await registry.invoke(invocation) }
        let proposal = try #require(await registry.pendingApprovals().first)
        try await registry.approve(proposal)
        await #expect(throws: PortholeError.self) { try await registry.invoke(invocation) }
        await #expect(throws: PortholeError.uncertainOperation) {
            try await registry.invoke(invocation)
        }
        #expect(await counter.count == 1)
    }

    @Test(arguments: [PortholeEffect.mutation, .unknown, .isolated])
    func observationsCannotRepeatEffectsThatRequireManualExecution(
        effect: PortholeEffect,
    ) async throws {
        let counter = PortholeTestCounter()
        let fixture = try await PortholeRuntimeObservationFixture.make(effect: effect) { _, _ in
            await .integer(Int64(counter.increment()))
        }
        await #expect(throws: PortholeError.self) {
            try await fixture.registry.startObservation(fixture.request(receiver: nil))
        }
        #expect(await counter.count == 0)
        #expect(await fixture.registry.pendingApprovals().isEmpty)
    }

    @Test func observationsUseFreshInvocationsAndDeliverOnlyTheLatestSequence() async throws {
        let counter = PortholeObservationInvocationCounter()
        let fixture = try await PortholeRuntimeObservationFixture
            .make(effect: .read) { invocation, _ in
                await counter.sample(invocation)
            }
        let request = fixture.request(receiver: nil)
        let reference = try await fixture.registry.startObservation(request)
        let first = try #require(try await fixture.registry.readObservation(
            reference,
            afterSequence: nil,
            waitMilliseconds: 10000,
        ).latestSample)
        let second = try #require(try await fixture.registry.readObservation(
            reference,
            afterSequence: first.sequence,
            waitMilliseconds: 10000,
        ).latestSample)
        #expect(second.sequence > first.sequence)
        #expect(second.value == .integer(second.sequence))
        #expect(second.invocationID != first.invocationID)
        let invocations = await counter.invocations
        #expect(Set(invocations).count == invocations.count)
        #expect(invocations.contains(request.id.rawValue) == false)
        #expect(invocations.contains(request.invocation.id) == false)
        try await fixture.registry.stopObservation(reference)
        await #expect(throws: PortholeError.observationEnded) {
            try await fixture.registry.readObservation(
                reference,
                afterSequence: nil,
                waitMilliseconds: 0,
            )
        }
        // Retrying a completed start returns its old reference, without starting another worker.
        #expect(try await fixture.registry.startObservation(request) == reference)
        await #expect(throws: PortholeError.observationEnded) {
            try await fixture.registry.readObservation(
                reference,
                afterSequence: nil,
                waitMilliseconds: 0,
            )
        }
    }

    @Test func genericObservationStartsReuseTheRequestIdentityAcrossOuterInvocations() async throws {
        let fixture = try await PortholeRuntimeObservationFixture
            .make(effect: .read) { _, _ in .integer(1) }
        let request = fixture.request(receiver: nil)
        for _ in 0 ..< 2 {
            let result = try await fixture.registry.invoke(.init(
                id: UUID(),
                scope: fixture.scope,
                capabilityID: PortholeObservationCapabilities.start,
                receiver: nil,
                arguments: .object(["request": .encoding(request)]),
            ))
            #expect(try result.decode(PortholeObservationReference.self) == request.reference)
        }
        let changed = PortholeObservationRequest(
            id: request.id,
            invocation: request.invocation,
            intervalMilliseconds: 2000,
        )
        await #expect(throws: PortholeError.operationConflict) {
            try await fixture.registry.invoke(.init(
                id: UUID(),
                scope: fixture.scope,
                capabilityID: PortholeObservationCapabilities.start,
                receiver: nil,
                arguments: .object(["request": .encoding(changed)]),
            ))
        }
        try await fixture.registry.stopObservation(request.reference)
    }

    @Test func observationStopBeforeStartDoesNotRunTheSelectedRead() async throws {
        let counter = PortholeTestCounter()
        let fixture = try await PortholeRuntimeObservationFixture.make(effect: .read) { _, _ in
            await .integer(Int64(counter.increment()))
        }
        let request = fixture.request(receiver: nil)
        try await fixture.registry.stopObservation(request.reference)
        try await fixture.registry.stopObservation(request.reference)
        await #expect(throws: PortholeError.observationEnded) {
            try await fixture.registry.startObservation(request)
        }
        #expect(await counter.count == 0)
    }

    @Test func observationsKeepReceiverLeasesBetweenPollsAndReleaseThemOnStop() async throws {
        let fixture = try await PortholeRuntimeObservationFixture
            .make(effect: .read) { invocation, registry in
                try await .string(registry.resolve(
                    invocation.receiver,
                    as: String.self,
                    in: invocation.scope,
                ))
            }
        let pool = PortholeObjectRetention.bounded(
            pool: .init(rawValue: "observation.test"),
            maximumCount: 1,
        )
        let receiver = try await fixture.registry.retain(
            "original",
            in: fixture.scope,
            retention: pool,
        )
        let reference = try await fixture.registry
            .startObservation(fixture.request(receiver: receiver))
        let snapshot = try await fixture.registry.readObservation(
            reference,
            afterSequence: nil,
            waitMilliseconds: 10000,
        )
        #expect(snapshot.latestSample?.value == .string("original"))
        await #expect(throws: PortholeError.capacityExceeded) {
            try await fixture.registry.retain("replacement", in: fixture.scope, retention: pool)
        }
        try await fixture.registry.stopObservation(reference)
        _ = try await fixture.registry.retain("replacement", in: fixture.scope, retention: pool)
        await #expect(throws: PortholeError.unknownObject) { try await fixture.registry.resolve(
            receiver,
            as: String.self,
            in: fixture.scope,
        ) }
    }

    @Test func disableEndsAnObservationBetweenSamplesWithoutRevivingIt() async throws {
        let fixture = try await PortholeRuntimeObservationFixture
            .make(effect: .read) { _, _ in .integer(1) }
        let request = fixture.request(receiver: nil)
        let reference = try await fixture.registry.startObservation(request)
        _ = try await fixture.registry.readObservation(
            reference,
            afterSequence: nil,
            waitMilliseconds: 10000,
        )
        await fixture.registry.setEnabled(false)
        await fixture.registry.setEnabled(true)
        await #expect(throws: PortholeError.observationEnded) {
            try await fixture.registry.readObservation(
                reference,
                afterSequence: nil,
                waitMilliseconds: 0,
            )
        }
        #expect(try await fixture.registry.startObservation(request) == reference)
        await #expect(throws: PortholeError.observationEnded) {
            try await fixture.registry.readObservation(
                reference,
                afterSequence: nil,
                waitMilliseconds: 0,
            )
        }
    }

    @Test func aLateNativeSampleCannotReturnToAnInvalidatedScope() async throws {
        let gate = PortholeTestGate()
        let fixture = try await PortholeRuntimeObservationFixture.make(effect: .read) { _, _ in
            await gate.enter()
            return .string("late")
        }
        let reference = try await fixture.registry.startObservation(fixture.request(receiver: nil))
        await gate.waitForArrival()
        let replacement = await fixture.registry.createScope(id: fixture.scope.id)
        await gate.release()
        await #expect(throws: PortholeError.staleScope) {
            try await fixture.registry.readObservation(
                reference,
                afterSequence: nil,
                waitMilliseconds: 0,
            )
        }
        #expect(try await fixture.registry.objectReferences(in: replacement).isEmpty)
    }

    @Test func oversizedObservationSamplesEndWithAnHonestFailure() async throws {
        let fixture = try await PortholeRuntimeObservationFixture.make(effect: .read) { _, _ in
            .string(String(repeating: "x", count: 1_048_577))
        }
        let reference = try await fixture.registry.startObservation(fixture.request(receiver: nil))
        let snapshot = try await fixture.registry.readObservation(
            reference,
            afterSequence: nil,
            waitMilliseconds: 10000,
        )
        guard case let .failed(message, lastSample) = snapshot.state
        else { Issue.record("Expected the sample limit to stop this observation"); return }
        #expect(message.contains("one MiB"))
        #expect(lastSample == nil)
        try await fixture.registry.stopObservation(reference)
    }

    @Test func observationOwnershipSurvivesNestedCallsAndRejectsCachedStartReplay() async throws {
        let fixture = try await PortholeRuntimeObservationFixture
            .make(effect: .read) { _, _ in .integer(1) }
        let owner = PortholeObservationOwnerID(rawValue: UUID())
        let otherOwner = PortholeObservationOwnerID(rawValue: UUID())
        let request = fixture.request(receiver: nil)
        let capability = PortholeCapability(
            id: .init(rawValue: "test.nestedObservation"),
            module: .init(rawValue: "Test"),
            name: "Nested observation",
            summary: "Test adapter",
            parameters: [],
            result: .any,
            effect: .isolated,
            source: nil,
            ownership: .adapter,
            availability: .callable,
        )
        try await fixture.registry.register(capability, in: fixture.scope) { _, registry in
            try await .encoding(registry.startObservation(request))
        }
        let result = try await PortholeObservationOwnership.$current.withValue(owner) {
            try await fixture.registry.invoke(.init(
                id: UUID(),
                scope: fixture.scope,
                capabilityID: capability.id,
                receiver: nil,
                arguments: .object([:]),
            ))
        }
        let reference = try result.decode(PortholeObservationReference.self)
        await PortholeObservationOwnership.$current.withValue(otherOwner) {
            await #expect(throws: PortholeError.operationConflict) {
                try await fixture.registry.startObservation(request)
            }
            await #expect(throws: PortholeError.operationConflict) {
                try await fixture.registry.readObservation(
                    reference,
                    afterSequence: nil,
                    waitMilliseconds: 0,
                )
            }
            await #expect(throws: PortholeError.operationConflict) {
                try await fixture.registry.stopObservation(reference)
            }
        }
        await fixture.registry.stopObservations(ownedBy: owner)
        await #expect(throws: PortholeError.observationEnded) {
            try await fixture.registry.readObservation(
                reference,
                afterSequence: nil,
                waitMilliseconds: 0,
            )
        }
        await PortholeObservationOwnership.$current.withValue(owner) {
            await #expect(throws: PortholeError.observationEnded) {
                try await fixture.registry.startObservation(fixture.request(receiver: nil))
            }
        }
    }

    @Test func disabledRegistryDoesNotExecute() async throws {
        let registry = PortholeRegistry(
            journal: PortholeOperationJournal(url: nil),
            objectLimit: 20,
        )
        let scope = await registry.createScope(id: .init(rawValue: "app"))
        await #expect(throws: PortholeError.disabled) { try await registry.capabilities(in: scope) }
    }
}

extension PortholeRegistryTests {
    @Test func coverageFollowsScopeReplacementAndActivationWithoutRegisteringInactiveCalls(
    ) async throws {
        let registry = PortholeRegistry(
            journal: PortholeOperationJournal(url: nil),
            objectLimit: 10,
            coverageModuleLimit: 1,
            coverageDeclarationLimit: 2,
            coverageByteLimit: 10000,
        )
        let scope = await registry.createScope(id: .init(rawValue: "coverage"))
        let row = PortholeRuntimeCoverageTestSupport.declaration("inactive")
        let json = try PortholeRuntimeCoverageTestSupport.json([
            PortholeRuntimeCoverageTestSupport.module([row]),
        ])
        try await PortholeRuntimeCoverageTestSupport.installSources(in: registry, scope: scope)
        try await registry.installCoverage(json, in: scope)
        await #expect(throws: PortholeError.disabled) {
            try await registry.coverage(
                in: scope,
                query: PortholeRuntimeCoverageTestSupport.query(),
            )
        }
        await registry.setEnabled(true)
        #expect(try await registry.coverage(
            in: scope,
            query: PortholeRuntimeCoverageTestSupport.query(),
        ).items.first?.state == .inactive)
        let invocation = PortholeInvocation(
            id: UUID(),
            scope: scope,
            capabilityID: row.id,
            receiver: nil,
            arguments: .object([:]),
        )
        await #expect(throws: PortholeError.unknownCapability(row.id)) {
            try await registry.invoke(invocation)
        }
        let mismatch = PortholeRuntimeCoverageTestSupport.capability(
            row,
            availability: .callable,
            name: "Conflicting name",
        )
        await #expect(throws: PortholeError.self) { try await registry.register(
            mismatch,
            in: scope,
        ) { _, _ in .null } }
        let capability = PortholeRuntimeCoverageTestSupport.capability(row, availability: .callable)
        try await registry.register(capability, in: scope) { _, _ in .integer(42) }
        #expect(try await registry.coverage(
            in: scope,
            query: PortholeRuntimeCoverageTestSupport.query(),
        ).items.first?.state == .callable)
        await #expect(throws: PortholeError.self) { try await registry.invoke(invocation) }
        #expect(await registry.pendingApprovals().count == 1)
        await registry.setEnabled(false)
        await registry.setEnabled(true)
        #expect(try await registry.coverageModules(in: scope, offset: 0, limit: 1).total == 1)
        let cancelledRead = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try await registry.coverage(
                in: scope,
                query: PortholeRuntimeCoverageTestSupport.query(),
            )
        }
        await #expect(throws: CancellationError.self) { try await cancelledRead.value }
        let replacement = await registry.createScope(id: scope.id)
        await #expect(throws: PortholeError.staleScope) { try await registry.installCoverage(
            json,
            in: scope,
        ) }
        await #expect(throws: PortholeError.staleScope) { try await registry.coverageModules(
            in: scope,
            offset: 0,
            limit: 1,
        ) }
        await #expect(throws: PortholeError
            .operationFailed("Source coverage has not been installed in this scope."))
        {
            try await registry.coverageModules(in: replacement, offset: 0, limit: 1)
        }
        try await PortholeRuntimeCoverageTestSupport.installSources(
            in: registry,
            scope: replacement,
        )
        try await registry.installCoverage(json, in: replacement)
        #expect(try await registry.coverage(
            in: replacement,
            query: PortholeRuntimeCoverageTestSupport.query(),
        ).items.first?.state == .inactive)
    }
}

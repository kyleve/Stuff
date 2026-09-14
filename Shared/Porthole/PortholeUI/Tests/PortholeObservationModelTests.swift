import Foundation
import PortholeRuntime
@testable import PortholeUI
import Testing

@MainActor
struct PortholeObservationModelTests {
    @Test func failedReadStopsSamplingAndPreservesItsLastEvidence() async throws {
        let executor = PortholeObservationUITestExecutor()
        defer { executor.finishPendingCalls() }
        let model = PortholeObservationModel()
        model.start(
            invocation: PortholeObservationUITestSupport
                .invocation(scope: PortholeRemoteUITestSupport.scope),
            execute: executor.execute,
        )
        #expect(await PortholeObservationUITestSupport.waitUntil { executor.reads.count == 1 })
        let reference = try #require(executor.reads.first?.observation)
        let sample = PortholeObservationSample(
            sequence: 1,
            invocationID: UUID(),
            capturedAt: Date(timeIntervalSince1970: 1_700_000_000),
            value: .string("last evidence"),
        )
        executor.deliver(.init(
            observation: reference,
            state: .failed(message: "Detector input is unavailable", lastSample: sample),
        ))
        #expect(await PortholeObservationUITestSupport.waitUntil { !model.isActive })
        guard case let .failed(session, message) = model.state else {
            Issue.record("Expected a stopped watch with its read failure"); return
        }
        #expect(session.sample == sample)
        #expect(message == "Detector input is unavailable")
        #expect(executor.stops == [reference])
    }

    @Test func stoppingBeforeStartReturnsUsesTheKnownIDAndCannotAttachToTheNextWatch() async throws {
        let executor = PortholeObservationUITestExecutor()
        defer { executor.finishPendingCalls() }
        executor.holdStarts = true
        let model = PortholeObservationModel()
        let scope = PortholeRemoteUITestSupport.scope
        model.start(
            invocation: PortholeObservationUITestSupport.invocation(scope: scope),
            execute: executor.execute,
        )
        #expect(await PortholeObservationUITestSupport.waitUntil { executor.starts.count == 1 })
        let first = try #require(executor.starts.first)
        model.stop()
        #expect(await PortholeObservationUITestSupport.waitUntil { !model.isActive })
        #expect(executor.stops == [.init(id: first.id, scope: scope)])

        executor.holdStarts = false
        model.start(
            invocation: PortholeObservationUITestSupport.invocation(scope: scope),
            execute: executor.execute,
        )
        #expect(await PortholeObservationUITestSupport.waitUntil { executor.starts.count == 2 })
        let second = try #require(executor.starts.last)
        #expect(await PortholeObservationUITestSupport
            .waitUntil { executor.hasPendingRead(second.id) })
        executor.releaseStart(first.id)
        let reference = PortholeObservationReference(id: second.id, scope: scope)
        executor.deliver(PortholeObservationUITestSupport.snapshot(
            reference: reference,
            sequence: 1,
            value: .string("new"),
        ))
        #expect(await PortholeObservationUITestSupport
            .waitUntil { model.state.session?.sample?.value == .string("new") })
        #expect(model.state.session?.reference == reference)
        #expect(!executor.reads.contains { $0.observation.id == first.id })
        model.stop()
        #expect(await PortholeObservationUITestSupport.waitUntil { !model.isActive })
    }

    @Test func delayedSampleCannotReplaceANewerScopeAndReadUsesTheSharedCursor() async throws {
        let executor = PortholeObservationUITestExecutor()
        defer { executor.finishPendingCalls() }
        let model = PortholeObservationModel()
        let oldScope = PortholeRemoteUITestSupport.scope
        model.start(
            invocation: PortholeObservationUITestSupport.invocation(scope: oldScope),
            execute: executor.execute,
        )
        #expect(await PortholeObservationUITestSupport.waitUntil { executor.reads.count == 1 })
        let oldReference = try #require(executor.reads.first?.observation)
        model.stop()
        #expect(await PortholeObservationUITestSupport.waitUntil { !model.isActive })

        let scope = PortholeScopeToken(id: oldScope.id, generation: UUID())
        model.start(
            invocation: PortholeObservationUITestSupport.invocation(scope: scope),
            execute: executor.execute,
        )
        #expect(await PortholeObservationUITestSupport.waitUntil { executor.reads.count == 2 })
        let reference = try #require(executor.reads.last?.observation)
        executor.deliver(PortholeObservationUITestSupport.snapshot(
            reference: reference,
            sequence: 4,
            value: .string("current"),
        ))
        #expect(await PortholeObservationUITestSupport.waitUntil { executor.reads.count == 3 })
        #expect(executor.reads.last?.afterSequence == 4)
        #expect(executor.reads.last?.waitMilliseconds == 10000)
        executor.deliver(PortholeObservationUITestSupport.snapshot(
            reference: oldReference,
            sequence: 9,
            value: .string("retired"),
        ))
        #expect(await PortholeObservationUITestSupport
            .waitUntil { executor.completedReads.contains(oldReference.id) })
        #expect(model.state.session?.reference.scope == scope)
        #expect(model.state.session?.sample?.value == .string("current"))
        #expect(model.state.session?.skippedSamples == true)
        model.stop()
        #expect(await PortholeObservationUITestSupport.waitUntil { !model.isActive })
    }

    @Test func failedStopStaysRecoverableAndDoesNotPermitAnotherWatch() async {
        let executor = PortholeObservationUITestExecutor()
        defer { executor.finishPendingCalls() }
        executor.stopFailures = 1
        let model = PortholeObservationModel()
        let invocation = PortholeObservationUITestSupport
            .invocation(scope: PortholeRemoteUITestSupport.scope)
        model.start(invocation: invocation, execute: executor.execute)
        #expect(await PortholeObservationUITestSupport.waitUntil { executor.reads.count == 1 })
        model.stop()
        #expect(await PortholeObservationUITestSupport.waitUntil {
            if case .stopFailed = model.state { true } else { false }
        })
        #expect(model.isActive)
        #expect(model.canStop)
        model.start(invocation: invocation, execute: executor.execute)
        #expect(executor.starts.count == 1)
        model.stop()
        #expect(await PortholeObservationUITestSupport.waitUntil { !model.isActive })
        #expect(executor.stops.count == 2)
        #expect(executor.stops.first == executor.stops.last)
    }
}

import Foundation
import PortholeCore
@testable import PortholeUI
import Testing

@MainActor
struct PortholeInvocationModelTests {
    @Test(
        arguments: [PortholeEffect.read, .isolated, .mutation, .unknown],
        [PortholeAvailability.callable, .inspectable, .unsupported("Unsupported fixture")],
    )
    func onlyCallableClassifiedReadsOfferWatch(
        effect: PortholeEffect,
        availability: PortholeAvailability,
    ) {
        let capability = PortholeCapability(
            id: .init(rawValue: "fixture.watch"),
            module: .init(rawValue: "Fixture"),
            name: "Watch",
            summary: "Read the fixture",
            parameters: [],
            result: .any,
            effect: effect,
            source: nil,
            ownership: .adapter,
            availability: availability,
        )
        let model = PortholeInvocationModel(
            capability: capability,
            objects: [],
            scope: PortholeRemoteUITestSupport.scope,
        )
        let expected = effect == .read && availability == .callable
        #expect(model.canWatch == expected)
        if !expected {
            var called = false
            model.watch { _ in called = true; return .null }
            #expect(!called)
            #expect(!model.observation.isActive)
        }
    }

    @Test func watchKeepsOriginalFormArgumentsAndCancellationStopsIt() async throws {
        let capability = PortholeCapability(
            id: .init(rawValue: "fixture.read"),
            module: .init(rawValue: "Fixture"),
            name: "Read",
            summary: "Read the fixture",
            parameters: [.init(name: "value", summary: "Value", schema: .string, required: true)],
            result: .any,
            effect: .read,
            source: nil,
            ownership: .adapter,
            availability: .callable,
        )
        let executor = PortholeObservationUITestExecutor()
        defer { executor.finishPendingCalls() }
        let model = PortholeInvocationModel(
            capability: capability,
            objects: [],
            scope: PortholeRemoteUITestSupport.scope,
        )
        model.fields[0].text = "original"
        model.watch(execute: executor.execute)
        model.fields[0].text = "changed"
        #expect(await PortholeObservationUITestSupport.waitUntil { executor.reads.count == 1 })
        let request = try #require(executor.starts.first)
        #expect(request.invocation.arguments == .object(["value": .string("original")]))
        model.cancel()
        #expect(await PortholeObservationUITestSupport.waitUntil { !model.observation.isActive })
        #expect(executor.stops == [.init(id: request.id, scope: request.invocation.scope)])
    }

    @Test func invalidIntegerInputBlocksExecutionAndShowsFailure() {
        let capability = PortholeCapability(
            id: .init(rawValue: "integer"),
            module: .init(rawValue: "Fixture"),
            name: "Integer",
            summary: "Integer",
            parameters: [.init(name: "count", summary: "Count", schema: .integer, required: true)],
            result: .any,
            effect: .read,
            source: nil,
            ownership: .adapter,
            availability: .callable,
        )
        let model = PortholeInvocationModel(
            capability: capability,
            objects: [],
            scope: PortholeRemoteUITestSupport.scope,
        )
        model.fields[0].integerText = "18446744073709551616"
        var executed = false
        model.run { _ in executed = true; return .null }
        #expect(!executed)
        guard case let .failed(message) = model.state
        else { Issue.record("Expected integer range failure"); return }
        #expect(message.contains("decimal integer"))
    }

    @Test func remoteApprovalRetryPreservesOriginalCallAfterFormEdits() async {
        let capability = PortholeRemoteUITestSupport.capability()
        let model = PortholeInvocationModel(
            capability: capability,
            objects: [],
            scope: PortholeRemoteUITestSupport.scope,
        )
        model.fields[0].text = "original"
        model.run { invocation in throw PortholeError.approvalRequired(.init(
            invocation: invocation,
            capability: capability,
        )) }
        let deadline = ContinuousClock.now.advanced(by: .seconds(2))
        while model.isRunning, ContinuousClock.now < deadline {
            await Task.yield()
        }
        guard case let .approvalRequired(proposal) = model.state
        else { Issue.record("Expected remote approval"); return }
        model.fields[0].text = "changed"
        var retried: PortholeInvocation?
        model.retryApproved { invocation in retried = invocation; return .string("done") }
        while model.isRunning, ContinuousClock.now < deadline {
            await Task.yield()
        }
        #expect(retried == proposal.invocation)
        #expect(retried?.arguments == .object(["value": .string("original")]))
        guard case .succeeded(.string("done")) = model.state
        else { Issue.record("Expected successful approved call"); return }
    }
}

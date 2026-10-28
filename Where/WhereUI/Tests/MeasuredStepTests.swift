import Foundation
import LifecycleKit
import PeriscopeCore
import Testing
@testable import WhereUI

/// A stand-in launch step whose run is scripted, so the decorator can be
/// exercised without a store, CoreLocation, or the real plan. It transforms its
/// input so a test can prove the wrapper is pass-through.
private struct ProbeStep: BudgetedLaunchStep {
    let id: LaunchStepID
    let budget: Duration
    var modes: LifecycleModeSet = .all
    var work: @MainActor () async throws -> Void = {}

    func run(_ input: String, _: LifecycleStepContext) async throws -> String {
        try await work()
        return input + "-ran"
    }
}

private struct ProbeFailure: Error {}

/// Covers `MeasuredStep`: that measuring a launch step is transparent to the
/// plan, and that each run lands as one span named after the step.
@MainActor
struct MeasuredStepTests {
    /// A logger over a private Periscope system, so a test reads only the spans
    /// it caused — never the process-wide launch traffic other suites emit.
    private func makeLogger(system: Periscope) -> Log<WhereLaunchLog> {
        Log(system: system)
    }

    private func makeSystem() -> Periscope {
        Periscope(configuration: Periscope.Configuration(), sinks: [])
    }

    private func context(_ id: LaunchStepID) -> LifecycleStepContext {
        LifecycleStepContext(stepID: id, reason: .userForeground)
    }

    @Test func spansEachRunUnderTheStepsID() async throws {
        let system = makeSystem()
        let step = ProbeStep(id: .resolveScope, budget: .seconds(1))
        let measured = MeasuredStep(wrapping: step, spanningInto: makeLogger(system: system))

        let output = try await measured.run("input", context(.resolveScope))

        // Pass-through: the wrapper returns exactly what the step produced.
        #expect(output == "input-ran")
        let records = system.recentRecords()
        let began = try #require(records.compactMap { $0.event as? SpanBegan }.first)
        let ended = try #require(records.compactMap { $0.event as? SpanEnded }.first)
        #expect(began.name == "step(resolve-scope)")
        #expect(ended.name == "step(resolve-scope)")
        // One span, not two halves of different ones.
        #expect(ended.spanID == began.spanID)
        #expect(ended.exit.mode == .success)
        #expect(ended.duration != nil)
    }

    /// The span has to report a failed step as failed: a launch that parks in
    /// `.failed` should be visible in the span history as an abnormal exit, not
    /// as a fast success.
    @Test func recordsAThrowingStepAsAFailedSpan() async throws {
        let system = makeSystem()
        let step = ProbeStep(
            id: .startSession,
            budget: .seconds(1),
            work: { throw ProbeFailure() },
        )
        let measured = MeasuredStep(wrapping: step, spanningInto: makeLogger(system: system))

        await #expect(throws: ProbeFailure.self) {
            try await measured.run("input", context(.startSession))
        }

        let ended = try #require(
            system.recentRecords().compactMap { $0.event as? SpanEnded }.first,
        )
        #expect(ended.name == "step(start-session)")
        #expect(ended.exit.mode == .failure)
    }

    /// A step that outlives its budget must warn *while* it runs — that's the
    /// signal that separates "slow" from "hung" — and still close normally.
    @Test func warnsWhileAStepOverrunsItsBudget() async throws {
        let system = makeSystem()
        let step = ProbeStep(
            id: .reminders,
            budget: .milliseconds(1),
            work: { try await Task.sleep(for: .milliseconds(50)) },
        )
        let measured = MeasuredStep(wrapping: step, spanningInto: makeLogger(system: system))

        _ = try await measured.run("input", context(.reminders))

        let overdue = try #require(
            system.recentRecords().compactMap { $0.event as? SpanOverdue }.first,
        )
        #expect(overdue.name == "step(reminders)")
        #expect(system.recentRecords().contains { ($0.event as? SpanEnded)?.exit.mode == .success })
    }

    /// The plan relies on `id` and `modes` surviving the wrapper: they key
    /// run-once memoization and the launch-reason gating, and `LaunchPlan`
    /// preconditions on both.
    @Test func forwardsTheWrappedStepsIdentityAndModes() {
        let step = ProbeStep(id: .captureToday, budget: .seconds(1), modes: .foreground)
        let measured = MeasuredStep(wrapping: step, spanningInto: makeLogger(system: makeSystem()))
        #expect(measured.id == .captureToday)
        #expect(measured.modes == .foreground)
    }

    /// Span names are what the tools group timings by, so each step must read as
    /// its own stable ID rather than a reflected Swift case name.
    @Test func namesSpansAfterTheStepIDNotTheSwiftCase() {
        #expect(String(describing: WhereLaunchLog.SpanName.step(.resolveScope)) ==
            "step(resolve-scope)")
        #expect(
            String(describing: WhereLaunchLog.SpanName.step(.issueAlerts)) == "step(issue-alerts)",
        )
        #expect(String(describing: WhereLaunchLog.SpanName.openLogStore) == "openLogStore")
        #expect(String(describing: WhereLaunchLog.SpanName.pruneHistory) == "pruneHistory")
    }
}

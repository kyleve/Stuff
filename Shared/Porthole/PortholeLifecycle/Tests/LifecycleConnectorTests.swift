import Foundation
import LifecycleKit
import PortholeCore
@testable import PortholeLifecycle
import Testing

@MainActor
struct LifecycleConnectorTests {
    private func launchState(_ runner: LifecycleRunner) async throws -> PortholeValue {
        let connector = LifecycleConnector(runner: runner)
        let source = connector.dataSources().first { $0.descriptor.id == "launch-state" }!
        let page = try await source.fetch(PortholeQuery())
        return try #require(page.rows.first)
    }

    @Test func reportsLaunchingBeforeRun() async throws {
        let runner = LifecycleRunner(reason: .userForeground, sequence: LifecycleSteps { [] })
        let row = try await launchState(runner)
        #expect(row["phase"]?.stringValue == "launching")
        #expect(row["reason"]?.stringValue?.contains("userForeground") == true)
    }

    @Test func reportsReadyAfterAllStepsFinish() async throws {
        let runner = LifecycleRunner(reason: .userForeground, sequence: LifecycleSteps {
            LifecycleStep.work("open-store") { _ in }
        })
        await runner.run()
        let row = try await launchState(runner)
        #expect(row["phase"]?.stringValue == "ready")
    }

    @Test func reportsFailureWithStepAndError() async throws {
        let runner = LifecycleRunner(reason: .userForeground, sequence: LifecycleSteps {
            LifecycleStep.work("bad-step") { _ in throw LaunchTestError.boom }
        })
        await runner.run()
        let row = try await launchState(runner)
        #expect(row["phase"]?.stringValue == "failed")
        #expect(row["failedStep"]?.stringValue?.contains("bad-step") == true)
        #expect(row["error"]?.stringValue?.contains("boom") == true)
    }
}

private enum LaunchTestError: Error { case boom }

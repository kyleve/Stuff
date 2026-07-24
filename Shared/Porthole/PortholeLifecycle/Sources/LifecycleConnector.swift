import Foundation
import LifecycleKit
import PortholeCore
import PortholeKit

/// A Porthole connector (id `lifecycle`) exposing an app's launch state from the
/// `LifecycleRunner` it already owns — inject that runner, never create one.
public final class LifecycleConnector: PortholeConnector {
    public let descriptor = PortholeConnectorDescriptor(
        id: "lifecycle",
        title: "Lifecycle",
        summary: "The app's launch phase, launch reason, the running step, and any launch failure.",
        version: 1,
    )

    private let runner: LifecycleRunner

    public init(runner: LifecycleRunner) {
        self.runner = runner
    }

    public func dataSources() -> [PortholeDataSource] {
        let runner = runner
        return [
            PortholeDataSource(
                descriptor: PortholeDataSourceDescriptor(
                    id: "launch-state",
                    title: "Launch state",
                    summary: "A single row describing the current launch phase and reason.",
                    rowSchema: .object([
                        "phase": .string(),
                        "reason": .string(),
                        "runningStep": .string(),
                        "failedStep": .string(),
                        "error": .string(),
                    ]),
                    filters: .object([:]),
                    supportsSubscription: false,
                ),
                fetch: { _ in await Self.snapshot(runner) },
            ),
        ]
    }

    @MainActor
    static func snapshot(_ runner: LifecycleRunner) -> PortholePage {
        let phase = runner.phase
        var object: [String: PortholeValue] = [
            "phase": .string(phaseName(phase)),
            "reason": .string(String(describing: runner.reason)),
        ]
        if let running = phase.runningStepID {
            object["runningStep"] = .string(String(describing: running))
        }
        if let failure = phase.failure {
            object["failedStep"] = .string(String(describing: failure.stepID))
            object["error"] = .string(String(describing: failure.error))
        }
        return PortholePage(rows: [.object(object)], totalCount: 1)
    }

    static func phaseName(_ phase: LifecyclePhase) -> String {
        switch phase {
            case .launching: "launching"
            case .running: "running"
            case .failed: "failed"
            case .ready: "ready"
        }
    }
}

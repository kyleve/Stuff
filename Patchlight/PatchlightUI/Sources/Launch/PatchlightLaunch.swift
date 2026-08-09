import Foundation
import LifecycleKit

public enum PatchlightLaunchStepID: String, Sendable {
    case prepareApplication = "prepare-application"
}

/// The value proving Patchlight's process prerequisites finished.
public struct PatchlightApplicationSession: Identifiable, Sendable {
    public let id: UUID
    public let model: PatchlightAppModel

    public init(id: UUID, model: PatchlightAppModel) {
        self.id = id
        self.model = model
    }
}

@MainActor
public enum PatchlightLaunch {
    /// Patchlight v1 has no headless runtime, so its application launcher must
    /// build a view tree from the first drive.
    public static func makeApplicationLauncher(
        dependencies: PatchlightApplicationDependencies,
    ) -> LifecycleRunner<PatchlightApplicationSession> {
        makeLauncher(reason: .userForeground, dependencies: dependencies)
    }

    public static func makeLauncher(
        reason: LifecycleReason,
        dependencies: PatchlightApplicationDependencies,
    ) -> LifecycleRunner<PatchlightApplicationSession> {
        LifecycleRunner(reason: reason, plan: plan(dependencies: dependencies))
    }

    public static func plan(dependencies: PatchlightApplicationDependencies)
        -> LaunchPlan<PatchlightLaunchStepID, Void, PatchlightApplicationSession>
    {
        LaunchPlan(PrepareApplicationStep(dependencies: dependencies))
    }
}

private struct PrepareApplicationStep: LifecycleStep {
    let id = PatchlightLaunchStepID.prepareApplication
    let modes: LifecycleModeSet = .all
    let dependencies: PatchlightApplicationDependencies

    func run(_: Void, _: LifecycleStepContext) async throws -> PatchlightApplicationSession {
        let model = PatchlightAppModel(dependencies: dependencies)
        await model.restore()
        return PatchlightApplicationSession(id: UUID(), model: model)
    }
}

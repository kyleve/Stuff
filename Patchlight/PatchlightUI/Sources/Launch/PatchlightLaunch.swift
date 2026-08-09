import Foundation
import LifecycleKit

public enum PatchlightLaunchStepID: String, Sendable {
    case prepareApplication = "prepare-application"
}

/// The value proving Patchlight's process prerequisites finished.
public struct PatchlightApplicationSession: Identifiable, Sendable {
    public let id: UUID

    public init(id: UUID) {
        self.id = id
    }
}

@MainActor
public enum PatchlightLaunch {
    public static func makeLauncher(
        reason: LifecycleReason,
    ) -> LifecycleRunner<PatchlightApplicationSession> {
        LifecycleRunner(reason: reason, plan: plan())
    }

    public static func plan()
        -> LaunchPlan<PatchlightLaunchStepID, Void, PatchlightApplicationSession>
    {
        LaunchPlan(PrepareApplicationStep())
    }
}

private struct PrepareApplicationStep: LifecycleStep {
    let id = PatchlightLaunchStepID.prepareApplication
    let modes: LifecycleModeSet = .all

    func run(_: Void, _: LifecycleStepContext) async throws -> PatchlightApplicationSession {
        PatchlightApplicationSession(id: UUID())
    }
}

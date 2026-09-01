import ThrowCore

/// Binds a fully projected hidden View to the activation and semantic frame that produced it.
struct PreparedProjectionExperience {
    let activationLease: ProjectionActivationLease
    let semanticFrame: ProjectionExperienceFrame
    let output: ProjectionFrameWorkerOutput

    var experienceID: ProjectionExperienceID {
        activationLease.experienceID
    }
}

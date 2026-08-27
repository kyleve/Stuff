import ThrowCore

/// Binds a fully projected hidden View to the activation and semantic frame that produced it.
struct PreparedProjectionExperience {
    let experienceID: ProjectionExperienceID
    let activationGeneration: UInt64
    let semanticFrame: ProjectionExperienceFrame
    let output: ProjectionFrameWorkerOutput
}

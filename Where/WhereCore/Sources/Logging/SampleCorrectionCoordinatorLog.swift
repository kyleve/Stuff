import PeriscopeCore

/// Privacy-preserving outcome of an Apply invalidated by another writer.
@LogScope("SampleCorrectionCoordinator")
enum SampleCorrectionCoordinatorLog {
    @LogEvent(
        "review-invalidated",
        message: "Correction review refreshed after a concurrent data change",
    )
    struct ReviewInvalidated {}
}

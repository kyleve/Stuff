import PeriscopeCore

/// Timed review and guarded save work. Errors remain available to the calling UI.
@LogScope("RecordingChoiceCoordinator")
enum RecordingChoiceCoordinatorLog {
    enum SpanName: Hashable {
        case review
        case save
    }
}

import PeriscopeCore

@LogScope("RecordingControlEditCoordinator")
enum RecordingControlEditCoordinatorLog {
    enum SpanName: Hashable {
        case history
        case previewIgnore
        case review
        case save
    }
}

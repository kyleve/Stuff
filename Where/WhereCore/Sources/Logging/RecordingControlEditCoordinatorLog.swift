import PeriscopeCore

@LogScope("RecordingControlEditCoordinator")
enum RecordingControlEditCoordinatorLog {
    enum SpanName: Hashable {
        case history
        case previewIgnore
        case previewPlace
        case review
        case save
    }
}

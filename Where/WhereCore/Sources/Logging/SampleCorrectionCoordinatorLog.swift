import PeriscopeCore

/// Privacy-preserving outcome of an Apply invalidated by another writer.
enum SampleCorrectionCoordinatorLog: LogEvent {
    case reviewInvalidated

    static let eventName = "SampleCorrectionCoordinator"

    var message: String {
        switch self {
            case .reviewInvalidated: "Correction review refreshed after a concurrent data change"
        }
    }
}

/// A live consumer of the shared projection frame.
public enum ProjectionOutput: Hashable, Sendable {
    case externalDisplay(ProjectionOutputID)
    case fullScreen(ProjectionOutputID)
    case preview(ProjectionOutputID)
    case calibration(ProjectionOutputID)
}

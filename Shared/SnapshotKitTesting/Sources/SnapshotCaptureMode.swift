/// Selects when an image assertion may draw a verified fixture.
public enum SnapshotCaptureMode: String, Sendable {
    /// Honor the fixture's measurement and final capture policies.
    case standard
    /// Draw the measured content on the same host after resolving its final size.
    /// Capture hooks, annotations, and explicit settle minimums keep their usual behavior.
    case afterMeasurement
    /// Fit and draw a synchronous, fixed-width intrinsic component on the native host.
    /// Components that require general sizing fall back to the standard renderer.
    case immediateComponent
}

/// A read-only boundary for the glance artifact shared with store-free
/// processes.
public protocol WhereSurfaceReading: Sendable {
    /// Returns `nil` when the app has never published an artifact.
    func read() throws -> WhereSurfaceDocument?
}

/// Controller summary of physical or on-device output demand.
public enum OutputHealth: Equatable, Sendable {
    case disconnected
    case preview
    case externalDisplay
    case fullScreen
    case multiple(Int)
}

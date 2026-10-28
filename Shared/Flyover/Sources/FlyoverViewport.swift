import CoreGraphics

/// The viewport a screen uses inside overview cards and the focused inspector.
public enum FlyoverViewport: Equatable, Hashable, Sendable {
    /// Follow the Flyover-wide phone/tablet and orientation controls.
    case device
    /// Render at a fixed component size, useful for widgets and snippets.
    case fixed(CGSize)
}

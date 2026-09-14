/// Native presentation follows controller changes even when a covered SwiftUI root defers
/// rendering.
@MainActor
protocol PortholePresentationObserving: AnyObject {
    func portholePresentationDidChange()
}

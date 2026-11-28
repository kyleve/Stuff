/// An observable change value for a repeatable action, including one with identical inputs.
public struct EventTrigger: Hashable, Sendable {
    private var generation: UInt64 = 0

    public init() {}

    public mutating func fire() {
        generation &+= 1
    }
}

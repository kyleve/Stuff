import QuartzCore

extension CATransaction {
    /// Runs `action` inside a transaction with implicit animations and animation
    /// duration disabled, so a root-view-controller swap or `layoutIfNeeded`
    /// during capture doesn't kick off an implicit Core Animation transition.
    @discardableResult
    static func performWithoutAnimation<Result>(_ action: () -> Result) -> Result {
        begin()
        setDisableActions(true)
        setAnimationDuration(0)
        defer { commit() }
        return action()
    }
}

/// Holds a lookup at its compatibility boundary until the test changes the handoff.
actor IntentHandoffBarrier {
    private(set) var arrived = false
    private var continuation: CheckedContinuation<Void, Never>?

    func wait() async {
        await withCheckedContinuation {
            continuation = $0
            arrived = true
        }
    }

    func release() {
        continuation?.resume()
        continuation = nil
    }
}

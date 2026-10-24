/// Stores at most one current error for each post-launch operation owner.
struct ThrowPostLaunchFailureLedger: Equatable {
    private var failuresByOwner: [ThrowPostLaunchFailure.Owner: ThrowPostLaunchFailure] = [:]

    init() {}

    var failures: [ThrowPostLaunchFailure] {
        ThrowPostLaunchFailure.Owner.allCases.compactMap { failuresByOwner[$0] }
    }

    func failure(
        for owner: ThrowPostLaunchFailure.Owner,
    ) -> ThrowPostLaunchFailure? {
        failuresByOwner[owner]
    }

    func recording(_ failure: ThrowPostLaunchFailure) -> Self {
        var ledger = self
        ledger.failuresByOwner[failure.owner] = failure
        return ledger
    }

    func resolving(_ owner: ThrowPostLaunchFailure.Owner) -> Self {
        var ledger = self
        ledger.failuresByOwner[owner] = nil
        return ledger
    }
}

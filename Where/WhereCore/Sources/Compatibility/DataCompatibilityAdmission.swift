/// One process-local grant. Returning to the same account does not revive an old grant.
public struct DataCompatibilityAdmission: Equatable, Sendable {
    public let domain: DataCompatibilityDomain
    let epoch: UInt64

    public var reviewContext: OnboardingReviewContext {
        OnboardingReviewContext(domain: domain, epoch: epoch)
    }
}

/// Identifies the account during in-memory onboarding review, including before it can open history.
public struct OnboardingReviewContext: Equatable, Sendable {
    let domain: DataCompatibilityDomain
    let epoch: UInt64
}

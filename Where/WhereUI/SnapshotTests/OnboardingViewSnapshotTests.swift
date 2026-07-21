import SnapshotKitTesting
import Testing
@testable import WhereUI

/// Image snapshots for `OnboardingView`; the matrix is declared via
/// `SnapshotProviding` in `OnboardingView.swift`.
@MainActor
@Suite(.snapshots(record: .missing))
struct OnboardingViewSnapshotTests {
    @Test func onboarding() async {
        await assertSnapshots(of: OnboardingView.self)
    }
}

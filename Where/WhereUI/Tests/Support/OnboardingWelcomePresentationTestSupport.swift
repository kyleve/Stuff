import Observation
import SwiftUI
import TestHostSupport
@testable import WhereUI

@MainActor
@Observable
final class OnboardingWelcomePresentationTestSupport {
    let model = OnboardingWelcomeModel()
    var destination = OnboardingWelcomePresentation.Destination.preparing
    var visible = true
    var contentAppeared = false
    var renderedDestination: OnboardingWelcomePresentation.Destination?
    var revealCount = 0

    struct Root: View {
        let support: OnboardingWelcomePresentationTestSupport

        var body: some View {
            Color.blue
                .onAppear { support.contentAppeared = true }
                .modifier(OnboardingWelcomePresentation(
                    model: support.model,
                    destination: support.destination,
                    isPresentationVisible: support.visible,
                    onReveal: { support.revealCount += 1 },
                ))
                .onChange(of: support.destination, initial: true) { _, destination in
                    support.renderedDestination = destination
                }
                .whereBroadwayRoot()
        }
    }

    func waitForState(_ predicate: () -> Bool) async throws {
        let deadline = ContinuousClock.now.advanced(by: .seconds(10))
        while !predicate() {
            try Task.checkCancellation()
            guard ContinuousClock.now < deadline else {
                throw TestHostError("Timed out waiting for the onboarding welcome presentation")
            }
            try await Task.sleep(for: .milliseconds(10))
        }
    }
}

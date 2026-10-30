import SwiftUI
import TestHostSupport
import Testing
@testable import WhereUI

@MainActor
struct OnboardingWelcomePresentationTests {
    @Test func warmsContentButStartsTheHoldOnlyWhenReadyAndVisible() async throws {
        let support = OnboardingWelcomePresentationTestSupport()
        support.model.present()
        try await show(UIHostingController(rootView: OnboardingWelcomePresentationTestSupport
                .Root(support: support)))
        { _ in
            try await support
                .waitForState {
                    support.contentAppeared && support.renderedDestination == .preparing
                }
            #expect(support.model.phase == .waiting)

            support.visible = false
            support.destination = .ready
            try await support.waitForState { support.renderedDestination == .ready }
            #expect(support.model.phase == .waiting)

            support.visible = true
            try await support.waitForState {
                if case .holding = support.model.phase { true } else { false }
            }
            support.visible = false
            try await support.waitForState { support.model.phase == .waiting }
            #expect(support.revealCount == 0)
        }
    }

    @Test func dismissesOnlyAfterTheHoldAndRevealAnimationComplete() async throws {
        let support = OnboardingWelcomePresentationTestSupport()
        support.destination = .ready
        support.model.present()
        try await show(UIHostingController(rootView: OnboardingWelcomePresentationTestSupport
                .Root(support: support)))
        { host in
            host.view.window?.layer.speed = 1
            try await support.waitForState {
                if case .holding = support.model.phase { true } else { false }
            }
            #expect(support.revealCount == 0)
            try await support.waitForState {
                if case .revealing = support.model.phase { true } else { false }
            }
            #expect(support.model.isPresented)
            #expect(support.revealCount == 0)
            try await support.waitForState { support.revealCount == 1 }
            #expect(!support.model.isPresented)
        }
    }

    @Test func aLaunchFailureRemovesTheCoverWithoutDismissingTheFailure() async throws {
        let support = OnboardingWelcomePresentationTestSupport()
        support.destination = .ready
        support.model.present()
        try await show(UIHostingController(rootView: OnboardingWelcomePresentationTestSupport
                .Root(support: support)))
        { _ in
            try await support.waitForState {
                if case .holding = support.model.phase { true } else { false }
            }
            support.destination = .failed
            try await support.waitForState { !support.model.isPresented }
            #expect(support.revealCount == 0)
        }
    }
}

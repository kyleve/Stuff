import Foundation
import Testing
@testable import WhereUI

@MainActor
struct OnboardingWelcomeModelTests {
    @Test func waitsForPresentationBeforeStartingTheMinimumHold() throws {
        let model = OnboardingWelcomeModel()
        #expect(!model.isPresented)
        model.present()
        #expect(model.phase == .waiting)

        let start = ContinuousClock.now
        let deadline = try #require(model.startHold(at: start, duration: .milliseconds(1500)))
        #expect(deadline == start.advanced(by: .milliseconds(1500)))
        #expect(!model.beginReveal(at: start.advanced(by: .seconds(1)), deadline: deadline))
        #expect(model.coversContent)
        #expect(model.beginReveal(at: deadline, deadline: deadline))
        #expect(!model.coversContent)
        #expect(model.isPresented)
        #expect(model.finishReveal(deadline: deadline))
        #expect(!model.isPresented)
        #expect(!model.finishReveal(deadline: deadline))
    }

    @Test func backgroundingRestartsTheHoldAndRejectsItsOldCompletion() throws {
        let model = OnboardingWelcomeModel()
        model.present()
        let start = ContinuousClock.now
        let old = try #require(model.startHold(at: start, duration: .milliseconds(1500)))
        model.pause()
        #expect(model.phase == .waiting)
        #expect(!model.beginReveal(at: old, deadline: old))

        let resumed = start.advanced(by: .seconds(10))
        let deadline = try #require(model.startHold(at: resumed, duration: .milliseconds(1500)))
        #expect(deadline == resumed.advanced(by: .milliseconds(1500)))
        #expect(model.beginReveal(at: deadline, deadline: deadline))
        model.pause()
        #expect(model.coversContent)
        #expect(!model.finishReveal(deadline: deadline))
    }

    @Test func anExistingHoldKeepsItsDeadlineAndCancellationRemovesTheCover() throws {
        let model = OnboardingWelcomeModel()
        model.present()
        let start = ContinuousClock.now
        let deadline = try #require(model.startHold(at: start, duration: .milliseconds(1500)))
        model.present()
        #expect(model
            .startHold(at: start.advanced(by: .seconds(1)), duration: .seconds(2)) == deadline)
        model.cancel()
        #expect(!model.isPresented)
        #expect(!model.beginReveal(at: deadline, deadline: deadline))
        #expect(!model.finishReveal(deadline: deadline))
    }
}

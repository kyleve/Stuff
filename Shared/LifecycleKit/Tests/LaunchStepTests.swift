@testable import LifecycleKit
import SwiftUI
import Testing

@MainActor
struct LaunchSequenceBuilderTests {
    @Test func builderPreservesDeclarationOrder() {
        let sequence = LaunchSequence {
            Work("a") { _ in }
            Work("b") { _ in }
            Work("c") { _ in }
        }
        #expect(sequence.steps.map(\.id) == ["a", "b", "c"])
    }

    @Test func builderSupportsConditionalInclusion() {
        func ids(includeMiddle: Bool) -> [String] {
            LaunchSequence {
                Work("a") { _ in }
                if includeMiddle {
                    Work("b") { _ in }
                }
                Work("c") { _ in }
            }.steps.map(\.id)
        }
        #expect(ids(includeMiddle: true) == ["a", "b", "c"])
        #expect(ids(includeMiddle: false) == ["a", "c"])
    }

    @Test func builderSupportsLoops() {
        let sequence = LaunchSequence {
            for name in ["x", "y", "z"] {
                Work(name) { _ in }
            }
        }
        #expect(sequence.steps.map(\.id) == ["x", "y", "z"])
    }
}

@MainActor
struct LaunchStepModifierTests {
    @Test func defaultStepAppliesToEveryReason() {
        let step = Work("a") { _ in }
        #expect(step.appliesTo(.userForeground))
        #expect(step.appliesTo(.background(.location)))
    }

    @Test func foregroundOnlyStepSkipsBackground() {
        let step = Work("a") { _ in }.modes(.foreground)
        #expect(step.appliesTo(.userForeground))
        #expect(!step.appliesTo(.background(.location)))
    }

    @Test func backgroundOnlyStepSkipsForeground() {
        let step = Work("a") { _ in }.modes(.background)
        #expect(!step.appliesTo(.userForeground))
        #expect(step.appliesTo(.background(.remoteNotification)))
    }

    @Test func defaultConditionIsTrue() async {
        let step = Work("a") { _ in }
        #expect(await step.condition())
    }

    @Test func whenModifierStoresPredicate() async {
        var flag = false
        let step = Work("a") { _ in }.when { flag }
        #expect(await step.condition() == false)
        flag = true
        #expect(await step.condition() == true)
    }

    @Test func plainWorkHasNoPresentation() {
        #expect(Work("a") { _ in }.presentation == nil)
    }

    @Test func presentingAttachesPresentation() {
        let step = Work("a") { _ in }.presenting { _ in Text("hi") }
        #expect(step.presentation != nil)
    }

    @Test func interactiveStepPresentsItsView() {
        let step = Interactive("onboarding") { _ in Text("onboarding") }
        #expect(step.presentation != nil)
    }
}

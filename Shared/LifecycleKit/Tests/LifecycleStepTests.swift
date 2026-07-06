@testable import LifecycleKit
import SwiftUI
import Testing

@MainActor
struct LifecycleStepsBuilderTests {
    @Test func builderPreservesDeclarationOrder() {
        let sequence = LifecycleSteps {
            LifecycleStep.work("a") { _ in }
            LifecycleStep.work("b") { _ in }
            LifecycleStep.work("c") { _ in }
        }
        #expect(sequence.steps.map(\.id) == ["a", "b", "c"] as [AnyHashable])
    }

    @Test func builderSupportsConditionalInclusion() {
        func ids(includeMiddle: Bool) -> [AnyHashable] {
            LifecycleSteps {
                LifecycleStep.work("a") { _ in }
                if includeMiddle {
                    LifecycleStep.work("b") { _ in }
                }
                LifecycleStep.work("c") { _ in }
            }.steps.map(\.id)
        }
        #expect(ids(includeMiddle: true) == ["a", "b", "c"] as [AnyHashable])
        #expect(ids(includeMiddle: false) == ["a", "c"] as [AnyHashable])
    }

    @Test func builderSupportsLoops() {
        let sequence = LifecycleSteps {
            for name in ["x", "y", "z"] {
                LifecycleStep.work(name) { _ in }
            }
        }
        #expect(sequence.steps.map(\.id) == ["x", "y", "z"] as [AnyHashable])
    }
}

@MainActor
struct LifecycleStepConfigurationTests {
    @Test func defaultStepAppliesToEveryReason() {
        let step = LifecycleStep.work("a") { _ in }
        #expect(step.appliesTo(.userForeground))
        #expect(step.appliesTo(.background(.location)))
    }

    @Test func foregroundOnlyStepSkipsBackground() {
        let step = LifecycleStep.work("a", modes: .foreground) { _ in }
        #expect(step.appliesTo(.userForeground))
        #expect(!step.appliesTo(.background(.location)))
    }

    @Test func backgroundOnlyStepSkipsForeground() {
        let step = LifecycleStep.work("a", modes: .background) { _ in }
        #expect(!step.appliesTo(.userForeground))
        #expect(step.appliesTo(.background(.remoteNotification)))
    }

    @Test func defaultConditionIsTrue() async {
        let step = LifecycleStep.work("a") { _ in }
        #expect(await step.condition())
    }

    @Test func workConditionGatesTheStep() async {
        let flag = MutableFlag()
        let step = LifecycleStep.work("a", condition: { flag.isOn }) { _ in }
        #expect(await step.condition() == false)
        flag.isOn = true
        #expect(await step.condition() == true)
    }

    @Test func initConditionGatesTheStep() async {
        let flag = MutableFlag()
        let step = LifecycleStep(id: "a", condition: { flag.isOn }) { _ in }
        #expect(await step.condition() == false)
        flag.isOn = true
        #expect(await step.condition() == true)
    }

    @Test func plainWorkHasNoPresentation() {
        #expect(LifecycleStep.work("a") { _ in }.presentation == nil)
    }

    @Test func presentingAttachesPresentation() {
        let step = LifecycleStep.work("a") { _ in }.presenting { _ in Text("hi") }
        #expect(step.presentation != nil)
    }

    @Test func interactiveStepPresentsItsView() {
        let step = LifecycleStep.interactive("onboarding") { _ in Text("onboarding") }
        #expect(step.presentation != nil)
    }
}

/// A mutable reference the `@MainActor` condition closures can flip *after*
/// they've been captured. `LifecycleStep.condition` is a `@MainActor` (and thus
/// `Sendable`) closure, so capturing and later mutating a plain local `var`
/// trips Swift 6's "mutated after capture by sendable closure"; reading through
/// a reference doesn't.
@MainActor
private final class MutableFlag {
    var isOn = false
}

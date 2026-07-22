@testable import LifecycleKit
import Testing

private struct FuzzError: Error {}

/// A small, *seedable* PRNG so each fuzz case is fully reproducible: a failure
/// reports the `seed`, and re-running that seed replays the exact sequence.
/// (`SystemRandomNumberGenerator` can't be seeded.)
private struct SplitMix64: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed
    }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}

/// A randomized plan-element description, kept separate from the built
/// `LaunchPlan` so the test can predict the expected outcome from the same
/// data the runner drives.
private struct FuzzElement {
    enum Kind {
        /// A required pass-through trunk step (`thenKeeping`).
        case keep
        /// A fire-and-forget child in its own `detached` group.
        case detachedChild
    }

    let id: String
    let kind: Kind
    let modes: LifecycleModeSet
    let throwsError: Bool
}

private func makeFuzzElements(_ rng: inout SplitMix64) -> [FuzzElement] {
    let modeChoices: [LifecycleModeSet] = [.all, .foreground, .background]
    let count = Int.random(in: 1 ... 8, using: &rng)
    return (0 ..< count).map { index in
        FuzzElement(
            id: "s\(index)",
            kind: Bool.random(using: &rng) ? .keep : .detachedChild,
            modes: modeChoices[Int.random(in: 0 ..< modeChoices.count, using: &rng)],
            throwsError: Double.random(in: 0 ... 1, using: &rng) < 0.15,
        )
    }
}

/// Property-based / adversarial coverage: rather than hand-pick plans, run
/// many randomized ones and check the runner's behavior against an
/// independent model. Complements the targeted runner tests.
@MainActor
struct LifecycleRunnerFuzzTests {
    /// For a random reason and a random mix of mode-gated / throwing trunk
    /// steps and detached children, the runner runs exactly the applicable
    /// trunk prefix (stopping at the first trunk throw, which parks
    /// `.failed`), spawns exactly the detached children the trunk reached,
    /// records exactly the detached failures, and otherwise reaches `.ready`.
    @Test(arguments: 0 ..< 200)
    func randomPlanLandsWhereTheModelPredicts(seed: Int) async {
        var rng = SplitMix64(seed: UInt64(seed))
        let foreground = Bool.random(using: &rng)
        let reason: LifecycleReason = foreground ? .userForeground : .background(.location)
        let fuzz = makeFuzzElements(&rng)

        var executedTrunk: [String] = []
        var executedDetached: Set<String> = []
        var plan = LaunchPlan(FixtureStep<Void, String>("root") { _, _ in "value" })
        for element in fuzz {
            switch element.kind {
                case .keep:
                    plan = plan.thenKeeping(
                        FixtureStep<String, Void>(element.id, modes: element.modes) { _, _ in
                            executedTrunk.append(element.id)
                            if element.throwsError { throw FuzzError() }
                        },
                    )
                case .detachedChild:
                    plan = plan.detached {
                        FixtureStep<String, Void>(element.id, modes: element.modes) { _, _ in
                            executedDetached.insert(element.id)
                            if element.throwsError { throw FuzzError() }
                        }
                    }
            }
        }
        let runner = LifecycleRunner(reason: reason, plan: plan)
        await runner.run()

        // Independent model of what should have happened.
        var expectedTrunk: [String] = []
        var expectedDetached: Set<String> = []
        var expectedDetachedFailures: Set<String> = []
        var expectedFailureID: String?
        for element in fuzz {
            guard element.modes.contains(reason.modeSet) else { continue }
            switch element.kind {
                case .keep:
                    expectedTrunk.append(element.id)
                    if element.throwsError { expectedFailureID = element.id }
                case .detachedChild:
                    expectedDetached.insert(element.id)
                    if element.throwsError { expectedDetachedFailures.insert(element.id) }
            }
            if expectedFailureID != nil { break }
        }

        #expect(executedTrunk == expectedTrunk)
        #expect(executedDetached == expectedDetached)
        #expect(Set(runner.detachedFailures.map { "\($0.stepID)" }) == expectedDetachedFailures)
        if let expectedFailureID {
            #expect(runner.phase.failed(at: expectedFailureID))
        } else {
            #expect(runner.phase.isReady)
            #expect(runner.phase.readyValue == "value")
        }
    }
}

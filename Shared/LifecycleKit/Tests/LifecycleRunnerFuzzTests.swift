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

    /// Trunk steps that throw their first N attempts then succeed: driving
    /// `retry()` resumes from the failed node each time (with its memoized
    /// input — earlier nodes never re-run) and, after exactly the number of
    /// injected failures, drains to `.ready` with every node having run once.
    @Test(arguments: 0 ..< 120)
    func retryDrainsFuzzedFlakyFailuresToReady(seed: Int) async throws {
        var rng = SplitMix64(seed: UInt64(seed))
        let count = Int.random(in: 1 ... 8, using: &rng)
        let ids = (0 ..< count).map { "s\($0)" }
        let failuresBeforeSuccess = (0 ..< count).map { _ in Int.random(in: 0 ... 2, using: &rng) }

        var attempts = [Int](repeating: 0, count: count)
        var succeeded: [String] = []
        var plan = LaunchPlan(FixtureStep<Void, String>("root") { _, _ in "value" })
        for index in 0 ..< count {
            plan = plan.thenKeeping(FixtureStep<String, Void>(ids[index]) { _, _ in
                attempts[index] += 1
                if attempts[index] <= failuresBeforeSuccess[index] { throw FuzzError() }
                succeeded.append(ids[index])
            })
        }
        let runner = LifecycleRunner(reason: .userForeground, plan: plan)

        await runner.run()

        let expectedRetries = failuresBeforeSuccess.reduce(0, +)
        var retries = 0
        // Bounded so a regression surfaces as a failed expectation, not a hang.
        while runner.phase.failure != nil, retries <= expectedRetries {
            let attemptsBeforeRetry = attempts.reduce(0, +)
            retries += 1
            runner.retry()
            // `retry()` spawns the drive; wait for it to settle. A *new* failure
            // is only trusted once an attempt has been made (attempts grew),
            // which rules out re-observing the pre-retry `.failed` phase.
            try await waitUntil {
                runner.phase.isReady
                    || (runner.phase.failure != nil && attempts.reduce(0, +) > attemptsBeforeRetry)
            }
        }

        #expect(runner.phase.isReady)
        #expect(retries == expectedRetries)
        #expect(succeeded == ids)
        for index in 0 ..< count {
            #expect(attempts[index] == failuresBeforeSuccess[index] + 1)
        }
    }
}

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

/// A randomized step description, kept separate from the built `LifecycleStep`
/// so the test can predict the expected outcome from the same data the runner
/// drives.
private struct FuzzStep {
    let id: String
    let modes: LifecycleModeSet
    let conditionPasses: Bool
    let throwsError: Bool
}

private func makeFuzzSteps(_ rng: inout SplitMix64) -> [FuzzStep] {
    let modeChoices: [LifecycleModeSet] = [.all, .foreground, .background]
    let count = Int.random(in: 1 ... 8, using: &rng)
    return (0 ..< count).map { index in
        FuzzStep(
            id: "s\(index)",
            modes: modeChoices[Int.random(in: 0 ..< modeChoices.count, using: &rng)],
            conditionPasses: Double.random(in: 0 ... 1, using: &rng) < 0.75,
            throwsError: Double.random(in: 0 ... 1, using: &rng) < 0.15,
        )
    }
}

/// Property-based / adversarial coverage: rather than hand-pick sequences, run
/// many randomized ones and check the runner's behavior against an independent
/// model. Complements the targeted runner tests.
@MainActor
struct LifecycleRunnerFuzzTests {
    /// For a random reason and a random mix of mode/condition/throwing steps, the
    /// runner runs exactly the applicable + condition-true prefix, stops at the
    /// first throw (parking `.failed` there), and otherwise reaches `.ready`.
    @Test(arguments: 0 ..< 200)
    func randomSequenceLandsWhereTheModelPredicts(seed: Int) async {
        var rng = SplitMix64(seed: UInt64(seed))
        let foreground = Bool.random(using: &rng)
        let reason: LifecycleReason = foreground ? .userForeground : .background(.location)
        let fuzz = makeFuzzSteps(&rng)

        var executed: [String] = []
        let runner = LifecycleRunner(reason: reason, sequence: LifecycleSteps {
            for step in fuzz {
                LifecycleStep
                    .work(step.id, modes: step.modes, condition: { step.conditionPasses }) { _ in
                        executed.append(step.id)
                        if step.throwsError { throw FuzzError() }
                    }
            }
        })
        await runner.run()

        // Independent model of what should have happened.
        var expectedExecuted: [String] = []
        var expectedFailureID: String?
        for step in fuzz {
            guard step.modes.contains(reason.modeSet), step.conditionPasses else { continue }
            expectedExecuted.append(step.id)
            if step.throwsError {
                expectedFailureID = step.id
                break
            }
        }

        #expect(executed == expectedExecuted)
        if let expectedFailureID {
            #expect(runner.phase.failed(at: expectedFailureID))
        } else {
            #expect(runner.phase.isReady)
        }
    }

    /// Steps that throw their first N attempts then succeed: driving `retry()`
    /// resumes from the failed step each time and, after exactly the number of
    /// injected failures, drains to `.ready` with every step having run once.
    @Test(arguments: 0 ..< 120)
    func retryDrainsFuzzedFlakyFailuresToReady(seed: Int) async throws {
        var rng = SplitMix64(seed: UInt64(seed))
        let count = Int.random(in: 1 ... 8, using: &rng)
        let ids = (0 ..< count).map { "s\($0)" }
        let failuresBeforeSuccess = (0 ..< count).map { _ in Int.random(in: 0 ... 2, using: &rng) }

        var attempts = [Int](repeating: 0, count: count)
        var succeeded: [String] = []
        let runner = LifecycleRunner(reason: .userForeground, sequence: LifecycleSteps {
            for index in 0 ..< count {
                LifecycleStep.work(ids[index]) { _ in
                    attempts[index] += 1
                    if attempts[index] <= failuresBeforeSuccess[index] { throw FuzzError() }
                    succeeded.append(ids[index])
                }
            }
        })

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

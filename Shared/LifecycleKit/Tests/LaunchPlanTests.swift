@testable import LifecycleKit
import Testing

@MainActor
struct LaunchPlanTests {
    private func context(_ id: AnyHashable = "test") -> LifecycleStepContext {
        LifecycleStepContext(stepID: id, reason: .userForeground)
    }

    @Test func trunkNodesAppearInDeclarationOrder() {
        let plan = LaunchPlan(FixtureStep<Void, Int>("open") { _, _ in 1 })
            .then(FixtureStep<Int, String>("session") { value, _ in "\(value)" })
            .gate(FixtureGate<String>("onboarding"))
            .thenKeeping(FixtureStep<String, Void>("auth") { _, _ in })
            .detached {
                FixtureStep<String, Void>("reminders") { _, _ in }
                FixtureStep<String, Void>("widgets") { _, _ in }
            }

        #expect(plan.nodes.flatMap(\.ids) == [
            "open",
            "session",
            "onboarding",
            "auth",
            "reminders",
            "widgets",
        ])
    }

    @Test func producingStepThreadsItsOutputToTheNextNode() async throws {
        let plan = LaunchPlan(FixtureStep<Void, Int>("open") { _, _ in 41 })
            .then(FixtureStep<Int, Int>("increment") { value, _ in value + 1 })

        guard case let .step(open) = plan.nodes[0], case let .step(increment) = plan.nodes[1]
        else {
            Issue.record("expected two step nodes")
            return
        }
        let opened = try await open.run((), context())
        let incremented = try await increment.run(opened, context())
        #expect(incremented as? Int == 42)
    }

    @Test func keepingStepPassesTheTrunkValueThrough() async throws {
        var ran = false
        let plan = LaunchPlan(FixtureStep<Void, String>("open") { _, _ in "session" })
            .thenKeeping(FixtureStep<String, Void>("keep") { _, _ in ran = true })

        guard case let .step(keep) = plan.nodes[1] else {
            Issue.record("expected a step node")
            return
        }
        let out = try await keep.run("session", context())
        #expect(ran)
        #expect(out as? String == "session")
    }

    @Test func gateNodeCarriesModesAndEvaluatesIsNeededAgainstTheTrunkValue() async {
        var seen: [String] = []
        let plan = LaunchPlan(FixtureStep<Void, String>("open") { _, _ in "session" })
            .gate(FixtureGate<String>("onboarding") { value in
                seen.append(value)
                return false
            })

        guard case let .gate(gate) = plan.nodes[1] else {
            Issue.record("expected a gate node")
            return
        }
        // Gates default to foreground-only: parking a headless launch on a tap
        // that can't come would deadlock it.
        #expect(gate.modes == .foreground)
        let needed = await gate.isNeeded("session")
        #expect(!needed)
        #expect(seen == ["session"])
    }

    @Test func detachedChildrenKeepTheirDeclaredModes() {
        let plan = LaunchPlan(FixtureStep<Void, String>("open") { _, _ in "session" })
            .detached {
                FixtureStep<String, Void>("capture", modes: .foreground) { _, _ in }
                FixtureStep<String, Void>("widgets") { _, _ in }
            }

        guard case let .detached(children) = plan.nodes[1] else {
            Issue.record("expected a detached group")
            return
        }
        #expect(children.map(\.id) == ["capture", "widgets"])
        #expect(children[0].modes == .foreground)
        #expect(children[1].modes == .all)
    }

    @Test func detachedBuilderSupportsConditionalsAndLoops() {
        func makePlan(includeExtra: Bool) -> LaunchPlan<String, Void, String> {
            LaunchPlan(FixtureStep<Void, String>("open") { _, _ in "session" })
                .detached {
                    FixtureStep<String, Void>("always") { _, _ in }
                    if includeExtra {
                        FixtureStep<String, Void>("extra") { _, _ in }
                    }
                    for index in 0 ..< 2 {
                        FixtureStep<String, Void>("loop-\(index)") { _, _ in }
                    }
                }
        }

        guard case let .detached(with) = makePlan(includeExtra: true).nodes[1],
              case let .detached(without) = makePlan(includeExtra: false).nodes[1]
        else {
            Issue.record("expected detached groups")
            return
        }
        #expect(with.map(\.id) == ["always", "extra", "loop-0", "loop-1"])
        #expect(without.map(\.id) == ["always", "loop-0", "loop-1"])
    }

    @Test func teardownPlansRootAtARealInput() async throws {
        // A teardown plan's root consumes a value (the thing being torn down)
        // rather than Void — the plan type carries that input.
        var erased: [String] = []
        let plan = LaunchPlan(FixtureStep<String, Void>("erase") { value, _ in
            erased.append(value)
        })
        guard case let .step(erase) = plan.nodes[0] else {
            Issue.record("expected a step node")
            return
        }
        _ = try await erase.run("session", context())
        #expect(erased == ["session"])
    }
}

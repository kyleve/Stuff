import Flagger
@testable import FlaggerUI

private struct WaitTimeoutError: Error {}

struct FlaggerModelFixture {
    let flagger: Flagger
    let model: FlaggerModel
}

struct UIFlags: FeatureFlagGroup {
    static let id = FeatureFlagGroupID("ui")
    static let name = "UI Flags"

    let enabled = Flag<Bool, LiveUpdating>(
        "enabled",
        name: "Enabled",
        detail: "Experimental renderer",
        default: false,
    )
    let launchStyle = Flag<String, ReadOnceOnLaunch>(
        "launch-style",
        name: "Launch Style",
        default: "standard",
    )
}

extension FeatureFlagGroups {
    var ui: UIFlags {
        self[UIFlags.self]
    }
}

enum UIFlagSource: FlagSource {
    static let id = FlagSourceID("ui-tests")
    static let name = "UI Tests"
    static let groups = FeatureFlagGroupRegistry { UIFlags.self }
}

@MainActor
func makeFlaggerModelFixture() async throws -> FlaggerModelFixture {
    let flagger = try await Flagger.open(
        sources: FlagSourceRegistry { UIFlagSource.self },
        storage: .inMemory,
    )
    return FlaggerModelFixture(flagger: flagger, model: FlaggerModel(flagger))
}

@MainActor
func makeFlaggerModel() async throws -> FlaggerModel {
    try await makeFlaggerModelFixture().model
}

@MainActor
func waitUntil(
    timeout: Duration = .seconds(2),
    _ condition: () -> Bool,
) async throws {
    let deadline = ContinuousClock.now.advanced(by: timeout)
    while condition() == false {
        if ContinuousClock.now >= deadline {
            throw WaitTimeoutError()
        }
        try await Task.sleep(for: .milliseconds(1))
    }
}

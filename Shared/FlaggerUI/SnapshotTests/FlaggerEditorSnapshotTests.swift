import Flagger
@testable import FlaggerUI
import SnapshotKitTesting
import SwiftUI
import Testing

private struct SnapshotFlags: FeatureFlagGroup {
    static let id = FeatureFlagGroupID("editor")
    static let name = "Editor"

    let boolean = Flag<Bool, LiveUpdating>(
        "boolean",
        name: "Boolean experiment",
        detail: "A live Boolean flag",
        default: true,
    )
    let configuration = Flag<[String: Int], ReadOnceOnLaunch>(
        "configuration",
        name: "JSON configuration",
        detail: "Applies when this scope is created",
        default: ["maximum": 10],
    )
}

private enum SnapshotFlagSource: FlagSource {
    static let id = FlagSourceID("snapshot-module")
    static let name = "Snapshot Module"
    static let groups = FeatureFlagGroupRegistry { SnapshotFlags.self }
}

@MainActor
struct FlaggerEditorSnapshotTests {
    @Test
    func editorStates() async throws {
        let flagger = try await Flagger.open(
            sources: FlagSourceRegistry { SnapshotFlagSource.self },
            storage: .inMemory,
        )
        let model = FlaggerModel(flagger)
        let configurations = SnapshotConfiguration.combinations(
            devices: [.iPhone],
            colorSchemes: [.light, .dark],
        )

        await assertSnapshots(
            of: FlaggerEditorView().environment(model),
            named: "Default",
            configurations: configurations,
        )

        await model.setOverride(
            .object(["maximum": .number(20)]),
            for: SnapshotFlags().configuration.id,
        )
        await assertSnapshots(
            of: FlaggerEditorView().environment(model),
            named: "PendingNextLifetime",
            configurations: configurations,
        )
    }
}

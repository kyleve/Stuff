import Flagger
@testable import FlaggerUI
import SnapshotKitTesting
import SwiftUI
import Testing

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

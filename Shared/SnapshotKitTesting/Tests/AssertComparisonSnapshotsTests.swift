import SnapshotKit
@testable import SnapshotKitTesting
import SwiftUI
import Testing

@MainActor
struct AssertComparisonSnapshotsTests {
    @Test func hostsFreshPanelsAndRunsBothReadinessHooks() async throws {
        var builds = 0
        var measurementHooks = 0
        var captureHooks = 0
        let snapshotCase = SnapshotCase.cutsheet(
            name: "Hooks",
            configurations: [SnapshotConfiguration()],
            measurementReadiness: .immediate,
            onReadyToMeasure: { measurementHooks += 1 },
            settle: .immediate,
            onReadyToSnapshot: { captureHooks += 1 },
        ) {
            for identity in ["one", "two"] {
                SnapshotPanel(id: .init(rawValue: identity), label: identity) {
                    builds += 1
                    return Color.blue.frame(height: 40)
                }
            }
        }
        #expect(builds == 0)
        let result = try await captureComparisonSheet(
            snapshotCase,
            configuration: SnapshotConfiguration(),
        )
        #expect(builds == 2)
        #expect(measurementHooks == 2)
        #expect(captureHooks == 2)
        #expect(result.layout.panels.count == 2)
    }

    @Test func accessibilityPanelsUseTheAnnotationPipeline() async throws {
        let snapshotCase = SnapshotCase.cutsheet(
            name: "Accessibility",
            configurations: [],
            settle: .immediate,
        ) {
            SnapshotPanel(id: .init(rawValue: "one"), label: "One") {
                Text("Accessible subject").padding()
            }
        }
        let standard = try await captureComparisonSheet(
            snapshotCase,
            configuration: SnapshotConfiguration(),
        )
        let annotated = try await captureComparisonSheet(
            snapshotCase,
            configuration: SnapshotConfiguration(snapshotType: .accessibility),
        )
        #expect(try annotated.render().pngData() != standard.render().pngData())
        #expect(annotated.layout.panels[0].bounds.height > standard.layout.panels[0].bounds.height)
    }
}

@testable import SnapshotKit
import SwiftUI
import Testing

private struct SampleComponent: SnapshotProviding {
    static var snapshots: [SnapshotCase] {
        SnapshotCase(name: "Compact", configurations: .componentRepresentative) {
            Color.blue
        }
        SnapshotCase(name: "Expanded", configurations: [SnapshotConfiguration()]) {
            Color.green
        }
    }
}

@MainActor
struct SnapshotProvidingTests {
    @Test func builderCollectsEveryCase() {
        let names = SampleComponent.snapshots.map(\.name)
        #expect(names == ["Compact", "Expanded"])
    }

    @Test func casesCarryTheirConfigurations() {
        let cases = SampleComponent.snapshots
        #expect(cases[0].configurations.count == [SnapshotConfiguration].componentRepresentative
            .count)
        #expect(cases[1].configurations == [SnapshotConfiguration()])
    }
}

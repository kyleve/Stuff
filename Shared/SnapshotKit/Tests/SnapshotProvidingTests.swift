@testable import SnapshotKit
import SwiftUI
import Testing

private struct SampleComponent: SnapshotProviding {
    static var snapshots: [SnapshotCase] {
        SnapshotCase(name: "Compact", configurations: .componentDefaults) {
            Color.blue
        }
        SnapshotCase(name: "Expanded", configurations: [SnapshotConfiguration()]) {
            Color.green
        }
    }
}

struct SnapshotProvidingTests {
    @Test func builderCollectsEveryCase() {
        let names = SampleComponent.snapshots.map(\.name)
        #expect(names == ["Compact", "Expanded"])
    }

    @Test func casesCarryTheirConfigurations() {
        let cases = SampleComponent.snapshots
        #expect(cases[0].configurations.count == [SnapshotConfiguration].componentDefaults.count)
        #expect(cases[1].configurations == [SnapshotConfiguration()])
    }
}

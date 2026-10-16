import Observation
import SnapshotKit
import SwiftUI

/// A ready hook changes each fixture once. Reusing the fixture makes the second image red.
@MainActor @Observable
final class SnapshotFixtureProbe {
    var mutations = 0
}

@MainActor
enum IndependentSnapshotProvider: SnapshotProviding {
    static var probes: [SnapshotFixtureProbe] = []

    static var snapshots: [SnapshotCase] {
        SnapshotCase(
            name: "Independent",
            configurations: [
                SnapshotConfiguration(device: .init(
                    name: "",
                    size: .fixed(CGSize(width: 20, height: 20)),
                )),
                SnapshotConfiguration(device: .init(
                    name: "second",
                    size: .fixed(CGSize(width: 20, height: 20)),
                )),
            ],
            onReadyToSnapshot: {
                precondition(!probes.isEmpty)
                probes[probes.count - 1].mutations += 1
            },
        ) {
            let probe = SnapshotFixtureProbe()
            probes.append(probe)
            return SnapshotFixtureProbeView(probe: probe)
        }
    }
}

private struct SnapshotFixtureProbeView: View {
    let probe: SnapshotFixtureProbe

    var body: some View {
        probe.mutations == 1 ? Color.green : Color.red
    }
}

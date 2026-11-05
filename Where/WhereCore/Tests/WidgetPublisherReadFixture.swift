import Foundation
@testable import WhereCore

/// Holds the first read so a newer result can publish before the original read finishes.
actor WidgetPublisherReadFixture: WidgetSnapshotReading {
    enum Failure: Error { case read }
    let gate: CompatibilityTestGate
    let firstFails: Bool
    private var reads = 0

    init(gate: CompatibilityTestGate, firstFails: Bool) {
        self.gate = gate
        self.firstFails = firstFails
    }

    func snapshot(asOf _: Date) async throws -> WidgetSnapshot {
        reads += 1
        let read = reads
        if read == 1 {
            await gate.suspend()
            if firstFails { throw Failure.read }
        }
        return WidgetSnapshot(
            day: .init(year: 2026, month: 3, day: 15),
            version: RecordingEvidencePolicy.version,
            dayRegions: .complete([.california]),
            totals: .complete([.california: read]),
        )
    }
}

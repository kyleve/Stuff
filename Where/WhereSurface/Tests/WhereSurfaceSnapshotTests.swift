import Foundation
import Testing
import WhereSurface

struct WhereSurfaceSnapshotTests {
    @Test func codableRoundTripPreservesPresentationData() throws {
        let california = WhereSurfaceSnapshot.Region(
            id: "us-CA",
            name: "California",
            emoji: "🌴",
            symbolName: "sun.max.fill",
        )
        let snapshot = WhereSurfaceSnapshot(
            day: Date(timeIntervalSinceReferenceDate: 10),
            todayRegions: [california],
            year: 2026,
            yearToDate: [.init(region: california, days: 132)],
        )

        let data = try JSONEncoder().encode(snapshot)
        let decoded = try JSONDecoder().decode(WhereSurfaceSnapshot.self, from: data)

        #expect(decoded == snapshot)
        #expect(decoded.yearToDate.first?.id == "us-CA")
    }
}

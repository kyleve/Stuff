import Foundation
import Testing
@testable import WhereCore

struct LocationMotionTests {
    @Test(arguments: [
        LocationMotion(
            speed: .init(metersPerSecond: 240, accuracyMetersPerSecond: 2),
            altitude: nil,
        ),
        LocationMotion(speed: nil, altitude: .init(meters: -20, accuracyMeters: 5)),
        LocationMotion(speed: nil, altitude: nil),
    ])
    func roundTripPreservesIndependentMeasurements(_ motion: LocationMotion) throws {
        let data = try JSONEncoder().encode(motion)
        #expect(try JSONDecoder().decode(LocationMotion.self, from: data) == motion)
    }
}

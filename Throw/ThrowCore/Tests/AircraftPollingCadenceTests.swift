import Foundation
import Testing
@testable import ThrowCore

struct AircraftPollingCadenceTests {
    @Test(arguments: [Duration.seconds(0.5), .seconds(10), .seconds(300)])
    func acceptsPositiveFractionalAndWholeSecondDurations(duration: Duration) throws {
        #expect(try AircraftPollingCadence(duration: duration).duration == duration)
    }

    @Test(arguments: [Duration.zero, .seconds(-0.5), .seconds(-10)])
    func rejectsZeroAndNegativeDurations(duration: Duration) {
        #expect(throws: AircraftPollingCadenceError.nonPositiveDuration) {
            try AircraftPollingCadence(duration: duration)
        }
    }
}

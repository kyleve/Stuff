import Foundation
import RegionKit
import Testing
@testable import WhereCore

struct RecordingPlaceTests {
    @Test func retainsHistoricalValidityAndRejectsInvalidCoordinates() throws {
        let validity = try RecordingAssessmentTestSupport.period(0, 100)
        let place = try RecordingPlace(
            id: .init(rawValue: UUID()),
            kind: .temporaryBase,
            coordinate: Coordinate(latitude: 37, longitude: -122),
            validity: validity,
        )
        #expect(place.validity.contains(RecordingAssessmentTestSupport.time(100)) == false)
        #expect(place.kind == .temporaryBase)
        #expect(throws: RecordingPlace.ValidationError.self) {
            try RecordingPlace(
                id: place.id,
                kind: .regularHome,
                coordinate: Coordinate(latitude: 91, longitude: 0),
                validity: validity,
            )
        }
    }
}

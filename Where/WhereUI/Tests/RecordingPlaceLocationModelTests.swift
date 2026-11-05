import Foundation
import RegionKit
import Testing
@testable import WhereUI

@MainActor
struct RecordingPlaceLocationModelTests {
    @Test func openingAnEmptyPickerDoesNotInventACoordinate() {
        let model = RecordingPlaceLocationModel(coordinate: nil)
        #expect(model.initialCoordinate == nil)
        #expect(model.coordinate == nil)
        model.latitude = 0
        #expect(model.coordinate == nil)
        model.longitude = 0
        #expect(model.coordinate == Coordinate(latitude: 0, longitude: 0))
    }

    @Test func mapSelectionAndManualCoordinatesUseTheSameValidatedDraft() {
        let coordinate = Coordinate(latitude: 40.71, longitude: -74)
        let model = RecordingPlaceLocationModel(coordinate: coordinate)
        #expect(model.coordinate == coordinate)
        model.select(.init(latitude: 51.5, longitude: 0))
        #expect(model.latitude == 51.5)
        #expect(model.longitude == 0)
        #expect(model.initialCoordinate == coordinate)
        for invalid in [Double.nan, .infinity, -91, 91] {
            model.latitude = invalid
            #expect(model.coordinate == nil)
        }
        model.latitude = 90
        model.longitude = -180
        #expect(model.coordinate != nil)
        model.longitude = 181
        #expect(model.coordinate == nil)
    }
}

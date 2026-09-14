import CoreLocation
import Foundation
import Testing
@testable import WhereCore

struct CoreLocationSourceTests {
    @Test func retainsValidSpeedAndAltitudeWithTheirAccuracies() {
        let location = Self.location(
            speed: 240,
            speedAccuracy: 2,
            altitude: 11000,
            verticalAccuracy: 8,
        )
        #expect(CoreLocationSource.motion(from: location) == LocationMotion(
            speed: .init(metersPerSecond: 240, accuracyMetersPerSecond: 2),
            altitude: .init(meters: 11000, accuracyMeters: 8),
        ))
    }

    @Test func invalidSpeedDoesNotDiscardValidBelowSeaLevelAltitude() {
        let location = Self.location(
            speed: -1,
            speedAccuracy: -1,
            altitude: -30,
            verticalAccuracy: 3,
        )
        #expect(CoreLocationSource.motion(from: location) == LocationMotion(
            speed: nil,
            altitude: .init(meters: -30, accuracyMeters: 3),
        ))
    }

    @Test(arguments: [-1.0, Double.nan, Double.infinity])
    func unavailableOrNonfiniteMeasurementsStayAbsent(_ invalid: Double) {
        let location = Self.location(
            speed: 220,
            speedAccuracy: invalid,
            altitude: 10000,
            verticalAccuracy: invalid,
        )
        #expect(CoreLocationSource.motion(from: location) == nil)
    }

    @Test func nonfiniteValuesStayAbsentEvenWithValidAccuracies() {
        let location = Self.location(
            speed: .infinity,
            speedAccuracy: 1,
            altitude: .nan,
            verticalAccuracy: 1,
        )
        #expect(CoreLocationSource.motion(from: location) == nil)
    }

    @Test func zeroSpeedAccuracyIsValidButZeroVerticalAccuracyIsUnavailable() {
        let location = Self.location(speed: 0, speedAccuracy: 0, altitude: 100, verticalAccuracy: 0)
        #expect(CoreLocationSource.motion(from: location) == LocationMotion(
            speed: .init(metersPerSecond: 0, accuracyMetersPerSecond: 0),
            altitude: nil,
        ))
    }

    private static func location(
        speed: Double,
        speedAccuracy: Double,
        altitude: Double,
        verticalAccuracy: Double,
    ) -> CLLocation {
        CLLocation(
            coordinate: CLLocationCoordinate2D(latitude: 40, longitude: -100),
            altitude: altitude,
            horizontalAccuracy: 5,
            verticalAccuracy: verticalAccuracy,
            course: 90,
            courseAccuracy: 1,
            speed: speed,
            speedAccuracy: speedAccuracy,
            timestamp: Date(timeIntervalSince1970: 1000),
        )
    }
}

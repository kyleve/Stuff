import Foundation
import RegionKit
import Testing
@_spi(Testing) import WhereCore

struct PlannedStayLocationVerifierTests {
    @Test func acceptsLocationInsideRegion() async throws {
        let (verifier, source) = try makeVerifier()
        source.setNextRequestedLocation(sample(
            at: Coordinate(latitude: 40.7128, longitude: -74.0060),
        ))

        let status = await verifier.status(for: .newYork, driftThreshold: .km1)

        #expect(status == .accepted)
    }

    @Test func acceptsLocationOutsideRegionWithinThreshold() async throws {
        let (verifier, source) = try makeVerifier()
        source.setNextRequestedLocation(sample(
            at: Coordinate(latitude: 39.5296, longitude: -119.8138),
        ))

        let status = await verifier.status(for: .california, driftThreshold: .km50)

        #expect(status == .accepted)
    }

    @Test func reportsLocationBeyondThreshold() async throws {
        let (verifier, source) = try makeVerifier()
        source.setNextRequestedLocation(sample(
            at: Coordinate(latitude: 35.6762, longitude: 139.6503),
        ))

        let status = await verifier.status(for: .newYork, driftThreshold: .km50)

        #expect(status == .outside)
    }

    @Test func reportsUnavailableWithoutCurrentFix() async throws {
        let (verifier, _) = try makeVerifier()

        let status = await verifier.status(for: .newYork, driftThreshold: .km1)

        #expect(status == .unavailable)
    }

    @Test func reportsUnavailableWithoutSelectedRegionGeometry() async throws {
        let (verifier, source) = try makeVerifier(
            attributor: RegionAttributor(for: [.california]),
        )
        source.setNextRequestedLocation(sample(
            at: Coordinate(latitude: 40.7128, longitude: -74.0060),
        ))

        let status = await verifier.status(for: .newYork, driftThreshold: .km1)

        #expect(status == .unavailable)
    }

    @Test func horizontalAccuracyDoesNotEnlargeThreshold() async throws {
        let (verifier, source) = try makeVerifier()
        source.setNextRequestedLocation(sample(
            at: Coordinate(latitude: 35.6762, longitude: 139.6503),
            horizontalAccuracy: 1_000_000,
        ))

        let status = await verifier.status(for: .newYork, driftThreshold: .km50)

        #expect(status == .outside)
    }

    private func makeVerifier(
        attributor: any RegionAttributing = RegionAttributor.shared,
    ) throws -> (PlannedStayLocationVerifier, ScriptedLocationSource) {
        let source = ScriptedLocationSource()
        let services = try WhereServices(
            store: SwiftDataStore.inMemory(),
            locationSource: source,
            attributor: attributor,
        )
        return (services.plannedStayLocation, source)
    }

    private func sample(
        at coordinate: Coordinate,
        horizontalAccuracy: Double = 5,
    ) -> LocationSample {
        LocationSample(
            timestamp: Date(timeIntervalSince1970: 0),
            coordinate: coordinate,
            horizontalAccuracy: horizontalAccuracy,
            source: .gpsSignificantChange,
        )
    }
}

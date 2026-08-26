import Foundation
import Testing
@testable import ThrowCore

struct AircraftModelsTests {
    @Test func aircraftIdentityDistinguishesICAOAndProviderMarkedValues() throws {
        let icao = try #require(AircraftID(kind: .icao, rawValue: "ABC123"))
        let other = try #require(
            AircraftID(kind: .providerMarkedNonICAO, rawValue: "ABC123"),
        )
        #expect(icao != other)
        #expect(icao.rawValue == "abc123")
    }

    @Test(arguments: ["", "   ", "\n\t"])
    func aircraftIdentityRejectsEmptyProviderValues(rawValue: String) {
        #expect(AircraftID(kind: .icao, rawValue: rawValue) == nil)
    }

    @Test func observationTrimsDisplayFields() throws {
        let original = try ThrowCoreFixture.observation(callsign: "  TEST1  ")
        #expect(original.callsign == "TEST1")
    }

    @Test func aircraftTypeDesignatorNormalizesProviderText() {
        #expect(AircraftTypeDesignator(rawValue: " b738 ")?.rawValue == "B738")
        #expect(AircraftTypeDesignator(rawValue: "too-long") == nil)
        #expect(AircraftEmitterCategory(providerValue: " a5 ") == .heavy)
    }

    @Test func sourceConfigurationNeverFallsBackToAnotherKind() throws {
        let rapid = try AircraftSourceConfiguration.adsbExchangeRapidAPI(
            ADSBExchangeConfiguration(
                pollingInterval: PollingInterval(seconds: 10),
                credentialID: .rapidAPI,
            ),
        )
        #expect(rapid.kind == .adsbExchangeRapidAPI)
    }

    @Test func onlyServerProviderFailuresAreRetryable() {
        #expect(AircraftSourceFailure.provider(statusCode: 500, retryAfterSeconds: nil).isRetryable)
        #expect(AircraftSourceFailure.provider(statusCode: 599, retryAfterSeconds: nil).isRetryable)
        #expect(
            AircraftSourceFailure.provider(statusCode: 404, retryAfterSeconds: nil)
                .isRetryable == false,
        )
        #expect(AircraftSourceFailure.quotaReached(retryAfterSeconds: nil).isRetryable)
        #expect(AircraftSourceFailure.transport(.localNetworkDenied).isRetryable)
    }

    @Test func impossibleGroundSpeedsAreRejectedAtDomainBoundaries() {
        #expect(throws: ThrowValidationError.self) {
            try ProjectionVelocity(
                groundTrack: nil,
                groundSpeedKnots: 2001,
                verticalRateFeetPerMinute: nil,
                turnRateDegreesPerSecond: nil,
                horizontalSource: .unavailable,
            )
        }
        #expect(throws: ThrowValidationError.self) {
            try ThrowCoreFixture.observation(groundSpeedKnots: 2001)
        }
    }

    @Test func aggregateDescriptionsRedactAircraftAndConfigurationData() throws {
        let aircraftIDSentinel = "aircraft-id-do-not-leak"
        let credentialIDSentinel = "credential-id-do-not-leak"
        let callsignSentinel = "CALLSIGN-DO-NOT-LEAK"
        let coordinateSentinel = "41.234567"
        let receiverSentinel = "receiver-do-not-leak.local"
        let observer = try ObserverPosition(
            coordinate: GeoCoordinate(latitude: 41.234567, longitude: -72.345678),
            altitude: Altitude(feet: 123),
        )
        let query = try AircraftQuery(
            observer: observer,
            center: observer.coordinate,
            viewport: .map(MapViewport(radius: NauticalMiles(value: 50))),
            includeGroundAircraft: false,
        )
        let observation = try AircraftObservation(
            id: #require(AircraftID(kind: .icao, rawValue: aircraftIDSentinel)),
            coordinate: GeoCoordinate(latitude: 41.334567, longitude: -72.345678),
            geometricAltitude: Altitude(feet: 10000),
            barometricAltitude: nil,
            airborneState: .airborne,
            groundTrack: Bearing(degrees: 90),
            trueHeading: nil,
            magneticHeading: nil,
            groundSpeedKnots: 400,
            verticalRateFeetPerMinute: nil,
            callsign: callsignSentinel,
            registration: nil,
            aircraftType: nil,
            emitterCategory: nil,
            airlineDesignator: nil,
            messageObservedAt: ThrowCoreFixture.date,
            positionObservedAt: ThrowCoreFixture.date,
            fetchedAt: ThrowCoreFixture.date,
            metadata: AircraftObservationMetadata(
                source: .adsbLol,
                positionSource: nil,
                messageCount: nil,
            ),
        )
        let snapshot = AircraftSnapshot(
            source: .adsbLol,
            fetchedAt: ThrowCoreFixture.date,
            observations: [observation],
        )
        let credentialID = AircraftCredentialID(rawValue: credentialIDSentinel)
        let exchangeConfiguration = try ADSBExchangeConfiguration(
            pollingInterval: PollingInterval(seconds: 10),
            credentialID: credentialID,
        )
        let readsbConfiguration = try ReadsbConfiguration(
            aircraftJSONURL: #require(
                URL(string: "http://\(receiverSentinel)/data/aircraft.json"),
            ),
        )
        let renderings = [
            String(describing: observation.id),
            String(reflecting: observation.id),
            String(describing: credentialID),
            String(reflecting: credentialID),
            String(describing: query),
            String(reflecting: query),
            String(describing: observation),
            String(reflecting: observation),
            String(describing: snapshot),
            String(reflecting: snapshot),
            String(describing: exchangeConfiguration),
            String(reflecting: exchangeConfiguration),
            String(describing: readsbConfiguration),
            String(reflecting: readsbConfiguration),
        ]

        for rendering in renderings {
            #expect(rendering.contains(aircraftIDSentinel) == false)
            #expect(rendering.contains(credentialIDSentinel) == false)
            #expect(rendering.contains(callsignSentinel) == false)
            #expect(rendering.contains(coordinateSentinel) == false)
            #expect(rendering.contains(receiverSentinel) == false)
        }
    }
}

import Foundation
import Testing
@testable import ThrowCore

struct ADSBExchangeV2DecoderTests {
    private let decoder = ADSBExchangeV2Decoder()

    @Test func normalizesV2AircraftFieldsAndMilliseconds() throws {
        let data = ThrowCoreFixture.adsbEnvelope(
            aircraftJSON: """
            {
              "hex":"abc123", "flight":" THROW1  ", "r":"N123TH", "t":"B738",
              "lat":37.1, "lon":-122.2, "alt_baro":12000, "alt_geom":12100,
              "gs":420.5, "track":361, "true_heading":359, "mag_heading":350,
              "baro_rate":-640, "seen":2, "seen_pos":4, "messages":99,
              "type":"adsb_icao", "category":"A3", "future_additive_field":{"safe":true}
            }
            """,
        )
        let snapshot = try decoder.decode(data, source: .adsbLol, fetchedAt: ThrowCoreFixture.date)
        let observation = try #require(snapshot.observations.first)
        #expect(observation.callsign == "THROW1")
        #expect(observation.geometricAltitude?.feet == 12100)
        #expect(observation.barometricAltitude?.feet == 12000)
        #expect(observation.groundTrack?.degrees == 1)
        #expect(observation.positionObservedAt == ThrowCoreFixture.date.addingTimeInterval(-4))
        #expect(observation.messageObservedAt == ThrowCoreFixture.date.addingTimeInterval(-2))
        #expect(observation.aircraftType?.rawValue == "B738")
        #expect(observation.emitterCategory == .large)
    }

    @Test(arguments: ["", "not-a-category", "D7"])
    func malformedOrUnsupportedEmitterCategoryIsIgnored(_ category: String) throws {
        let data = ThrowCoreFixture.adsbEnvelope(
            aircraftJSON: """
            {"hex":"abc123", "lat":37, "lon":-122, "category":"\(category)"}
            """,
        )
        let observation = try #require(
            decoder.decode(data, source: .adsbLol, fetchedAt: .now).observations.first,
        )
        #expect(observation.emitterCategory == nil)
    }

    @Test func recognizesGroundAndProviderMarkedNonICAOIdentity() throws {
        let data = ThrowCoreFixture.adsbEnvelope(
            aircraftJSON: """
            {"hex":"~other42", "lat":37, "lon":-122, "alt_baro":"ground"}
            """,
        )
        let snapshot = try decoder.decode(data, source: .adsbExchangeRapidAPI, fetchedAt: .now)
        let observation = try #require(snapshot.observations.first)
        #expect(observation.id.kind == .providerMarkedNonICAO)
        #expect(observation.id.rawValue == "other42")
        #expect(observation.airborneState == .ground)
        #expect(observation.barometricAltitude == nil)
    }

    @Test func altitudeLessPositionRemainsAvailableForMap() throws {
        let data = ThrowCoreFixture.adsbEnvelope(
            aircraftJSON: """
            {"hex":"abc123", "lat":37, "lon":-122}
            """,
        )
        let observation = try #require(
            decoder.decode(data, source: .adsbLol, fetchedAt: .now).observations.first,
        )
        #expect(observation.preferredSkyAltitude == nil)
        #expect(observation.airborneState == .unknown)
    }

    @Test func missingCoordinatesAreIgnoredRatherThanZeroFilled() throws {
        let data = ThrowCoreFixture.adsbEnvelope(
            aircraftJSON: """
            {"hex":"missing", "alt_baro":10000},
            {"hex":"present", "lat":1, "lon":2, "alt_baro":10000}
            """,
        )
        let snapshot = try decoder.decode(data, source: .adsbLol, fetchedAt: .now)
        #expect(snapshot.observations.map(\.id.rawValue) == ["present"])
    }

    @Test func secondTimestampIsNotDividedAgain() throws {
        let data = Data(
            """
            {"now":1700000000,"ac":[{"hex":"a","lat":0,"lon":0,"seen_pos":5}]}
            """.utf8,
        )
        let observation = try #require(
            decoder.decode(data, source: .adsbLol, fetchedAt: .now).observations.first,
        )
        #expect(observation.positionObservedAt == ThrowCoreFixture.date.addingTimeInterval(-5))
    }

    @Test func malformedAircraftIsDroppedWithoutRejectingValidNeighbors() throws {
        let data = ThrowCoreFixture.adsbEnvelope(
            aircraftJSON: """
            {"hex":"bad", "lat":0, "lon":0, "alt_baro":"not-an-altitude"},
            {"hex":"good", "lat":1, "lon":2, "alt_baro":10000}
            """,
        )
        let snapshot = try decoder.decode(data, source: .adsbLol, fetchedAt: .now)
        #expect(snapshot.observations.map(\.id.rawValue) == ["good"])
    }

    @Test func entirelyMalformedAircraftPayloadFailsInsteadOfAppearingHealthyEmpty() {
        let data = ThrowCoreFixture.adsbEnvelope(
            aircraftJSON: """
            {"hex":"bad", "lat":0, "lon":0, "alt_baro":"not-an-altitude"}
            """,
        )

        #expect(throws: ADSBV2DecodingError.invalidEnvelope) {
            try decoder.decode(data, source: .adsbLol, fetchedAt: .now)
        }
    }

    @Test func recordsWithoutCoordinatesCanStillProduceHealthyEmptySnapshot() throws {
        let data = ThrowCoreFixture.adsbEnvelope(
            aircraftJSON: """
            {"hex":"missing-position", "alt_baro":10000}
            """,
        )

        let snapshot = try decoder.decode(data, source: .adsbLol, fetchedAt: .now)
        #expect(snapshot.observations.isEmpty)
    }

    @Test func missingRequiredIdentityIsSchemaFailure() {
        let data = ThrowCoreFixture.adsbEnvelope(
            aircraftJSON: """
            {"lat":37,"lon":-122,"alt_baro":10000}
            """,
        )

        #expect(throws: ADSBV2DecodingError.invalidEnvelope) {
            try decoder.decode(data, source: .adsbLol, fetchedAt: .now)
        }
    }

    @Test(arguments: ["seen", "seen_pos"])
    func negativeObservationAgeIsSchemaFailure(field: String) {
        let data = ThrowCoreFixture.adsbEnvelope(
            aircraftJSON: """
            {"hex":"abc123","lat":37,"lon":-122,"\(field)":-1}
            """,
        )

        #expect(throws: ADSBV2DecodingError.invalidEnvelope) {
            try decoder.decode(data, source: .adsbLol, fetchedAt: .now)
        }
    }

    @Test func decodingWorkerAlsoPerformsExactLocalPostFilter() async throws {
        let worker = AircraftDecodingWorker(decoder: decoder)
        let data = ThrowCoreFixture.adsbEnvelope(
            aircraftJSON: """
            {"hex":"near", "lat":37.01, "lon":-122, "alt_baro":10000},
            {"hex":"outside", "lat":37.2, "lon":-122, "alt_baro":10000}
            """,
        )

        let snapshot = try await worker.decodeCloudSnapshot(
            data,
            source: .adsbLol,
            fetchedAt: ThrowCoreFixture.date,
            query: ThrowCoreFixture.mapQuery(radius: 5),
        )
        #expect(snapshot.observations.map(\.id.rawValue) == ["near"])
    }

    @Test func malformedEnvelopeStillFailsAsSchemaMismatch() {
        let data = Data("{\"ac\":{\"not\":\"an array\"}}".utf8)
        #expect(throws: ADSBV2DecodingError.invalidEnvelope) {
            try decoder.decode(data, source: .adsbLol, fetchedAt: .now)
        }
    }

    @Test(arguments: ["nan", "inf", "-inf"])
    func nonFiniteProviderTimestampIsRejected(value: String) {
        let data = Data("{\"now\":\"\(value)\",\"ac\":[]}".utf8)
        #expect(throws: ADSBV2DecodingError.invalidEnvelope) {
            try decoder.decode(data, source: .adsbLol, fetchedAt: .now)
        }
    }
}

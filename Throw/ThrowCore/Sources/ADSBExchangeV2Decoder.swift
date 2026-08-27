import Foundation

enum ADSBV2DecodingError: Error, Equatable {
    case invalidEnvelope
}

/// Normalizes the common ADS-B Exchange v2 aircraft envelope used by all
/// three v1 providers. Unknown additive fields are ignored. Individual bad
/// records are lossy, but an otherwise empty malformed payload is a schema error.
struct ADSBExchangeV2Decoder {
    init() {}

    func decode(
        _ data: Data,
        source: AircraftSourceKind,
        fetchedAt: Date,
    ) throws -> AircraftSnapshot {
        let envelope: Envelope
        do {
            envelope = try JSONDecoder().decode(Envelope.self, from: data)
        } catch {
            throw ADSBV2DecodingError.invalidEnvelope
        }

        let providerNow = envelope.now.map { normalizedTimestamp($0.value) }
        let referenceDate = providerNow.map(Date.init(timeIntervalSince1970:)) ?? fetchedAt
        var observations: [AircraftObservation] = []
        observations.reserveCapacity(envelope.aircraft.count)
        var malformedRecordCount = 0
        var intentionallyIgnoredPositionCount = 0

        for lossyAircraft in envelope.aircraft {
            try Task.checkCancellation()
            guard let aircraft = lossyAircraft.value else {
                malformedRecordCount += 1
                continue
            }
            guard let rawID = aircraft.hex?.trimmingCharacters(in: .whitespacesAndNewlines),
                  rawID.isEmpty == false
            else {
                malformedRecordCount += 1
                continue
            }

            let identity: AircraftID
            if rawID.hasPrefix("~") {
                let value = String(rawID.dropFirst())
                guard let decodedIdentity = AircraftID(
                    kind: .providerMarkedNonICAO,
                    rawValue: value,
                ) else {
                    malformedRecordCount += 1
                    continue
                }
                identity = decodedIdentity
            } else {
                guard let decodedIdentity = AircraftID(kind: .icao, rawValue: rawID) else {
                    malformedRecordCount += 1
                    continue
                }
                identity = decodedIdentity
            }

            guard (aircraft.seen?.value ?? 0) >= 0,
                  (aircraft.seenPosition?.value ?? 0) >= 0
            else {
                malformedRecordCount += 1
                continue
            }
            guard let latitude = aircraft.latitude?.value,
                  let longitude = aircraft.longitude?.value
            else {
                intentionallyIgnoredPositionCount += 1
                continue
            }

            do {
                let coordinate = try GeoCoordinate(latitude: latitude, longitude: longitude)
                let barometricAltitude: Altitude?
                let airborneState: AircraftAirborneState
                switch aircraft.barometricAltitude {
                    case let .altitude(value):
                        barometricAltitude = try Altitude(feet: value)
                        airborneState = .airborne
                    case .ground:
                        barometricAltitude = nil
                        airborneState = .ground
                    case nil:
                        barometricAltitude = nil
                        airborneState = aircraft.geometricAltitude == nil ? .unknown : .airborne
                }

                let geometricAltitude: Altitude? = if let value = aircraft.geometricAltitude?
                    .value
                {
                    try Altitude(feet: value)
                } else {
                    nil
                }

                try observations.append(
                    AircraftObservation(
                        id: identity,
                        coordinate: coordinate,
                        geometricAltitude: geometricAltitude,
                        barometricAltitude: barometricAltitude,
                        airborneState: airborneState,
                        groundTrack: aircraft.track.map { try Bearing(degrees: $0.value) },
                        trueHeading: aircraft.trueHeading.map { try Bearing(degrees: $0.value) },
                        magneticHeading: aircraft.magneticHeading
                            .map { try Bearing(degrees: $0.value) },
                        groundSpeedKnots: aircraft.groundSpeed?.value,
                        verticalRateFeetPerMinute: aircraft.geometricRate?.value ?? aircraft
                            .barometricRate?.value,
                        callsign: aircraft.flight,
                        registration: aircraft.registration,
                        aircraftType: aircraft.aircraftType.flatMap(
                            AircraftTypeDesignator.init(rawValue:),
                        ),
                        emitterCategory: aircraft.emitterCategory.flatMap(
                            AircraftEmitterCategory.init(providerValue:),
                        ),
                        airlineDesignator: nil,
                        messageObservedAt: referenceDate.addingTimeInterval(
                            -(aircraft.seen?.value ?? 0),
                        ),
                        positionObservedAt: referenceDate.addingTimeInterval(
                            -(aircraft.seenPosition?.value ?? 0),
                        ),
                        fetchedAt: fetchedAt,
                        metadata: AircraftObservationMetadata(
                            source: source,
                            positionSource: aircraft.positionSource,
                            messageCount: aircraft.messages,
                        ),
                    ),
                )
            } catch {
                malformedRecordCount += 1
                continue
            }
        }
        if observations.isEmpty,
           malformedRecordCount > 0,
           intentionallyIgnoredPositionCount == 0
        {
            throw ADSBV2DecodingError.invalidEnvelope
        }
        return AircraftSnapshot(source: source, fetchedAt: fetchedAt, observations: observations)
    }

    private func normalizedTimestamp(_ timestamp: Double) -> TimeInterval {
        timestamp >= 100_000_000_000 ? timestamp / 1000 : timestamp
    }
}

/// Runs response adaptation, normalization, and exact local filtering away
/// from the polling coordinator's actor.
actor AircraftDecodingWorker {
    private let decoder: ADSBExchangeV2Decoder

    init(decoder: ADSBExchangeV2Decoder) {
        self.decoder = decoder
    }

    func decodeCloudSnapshot(
        _ data: Data,
        source: AircraftSourceKind,
        fetchedAt: Date,
        query: AircraftQuery,
    ) throws -> AircraftSnapshot {
        try Task.checkCancellation()
        let decoded = try decoder.decode(data, source: source, fetchedAt: fetchedAt)
        try Task.checkCancellation()
        let observations = try CloudAircraftQuery.postFilter(decoded.observations, for: query)
        try Task.checkCancellation()
        return AircraftSnapshot(source: source, fetchedAt: fetchedAt, observations: observations)
    }

    func decodeReadsbSnapshot(
        _ data: Data,
        fetchedAt: Date,
        query: AircraftQuery,
    ) throws -> AircraftSnapshot {
        try Task.checkCancellation()
        let adapted = try ReadsbEnvelopeAdapter.adapt(data)
        return try decodeCloudSnapshot(
            adapted,
            source: .readsb,
            fetchedAt: fetchedAt,
            query: query,
        )
    }
}

private struct Envelope: Decodable {
    let aircraft: [LossyAircraftDTO]
    let now: FlexibleDouble?

    enum CodingKeys: String, CodingKey {
        case aircraft = "ac"
        case now
    }
}

/// Consumes one array element even when that provider record has a malformed
/// field, allowing the rest of a valid envelope to remain usable.
private struct LossyAircraftDTO: Decodable {
    let value: AircraftDTO?

    init(from decoder: any Decoder) throws {
        value = try? AircraftDTO(from: decoder)
    }
}

private struct AircraftDTO: Decodable {
    let hex: String?
    let flight: String?
    let registration: String?
    let aircraftType: String?
    let emitterCategory: String?
    let barometricAltitude: BarometricAltitudeDTO?
    let geometricAltitude: FlexibleDouble?
    let groundSpeed: FlexibleDouble?
    let track: FlexibleDouble?
    let trueHeading: FlexibleDouble?
    let magneticHeading: FlexibleDouble?
    let barometricRate: FlexibleDouble?
    let geometricRate: FlexibleDouble?
    let latitude: FlexibleDouble?
    let longitude: FlexibleDouble?
    let seen: FlexibleDouble?
    let seenPosition: FlexibleDouble?
    let positionSource: String?
    let messages: Int?

    enum CodingKeys: String, CodingKey {
        case hex
        case flight
        case registration = "r"
        case aircraftType = "t"
        case emitterCategory = "category"
        case barometricAltitude = "alt_baro"
        case geometricAltitude = "alt_geom"
        case groundSpeed = "gs"
        case track
        case trueHeading = "true_heading"
        case magneticHeading = "mag_heading"
        case barometricRate = "baro_rate"
        case geometricRate = "geom_rate"
        case latitude = "lat"
        case longitude = "lon"
        case seen
        case seenPosition = "seen_pos"
        case positionSource = "type"
        case messages
    }
}

private struct FlexibleDouble: Decodable {
    let value: Double

    init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        let decodedValue: Double
        if let double = try? container.decode(Double.self) {
            decodedValue = double
        } else if let text = try? container.decode(String.self), let double = Double(text) {
            decodedValue = double
        } else {
            throw DecodingError.typeMismatch(
                Double.self,
                DecodingError.Context(
                    codingPath: decoder.codingPath,
                    debugDescription: "Expected a numeric value",
                ),
            )
        }
        guard decodedValue.isFinite else {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Expected a finite numeric value",
            )
        }
        value = decodedValue
    }
}

private enum BarometricAltitudeDTO: Decodable {
    case altitude(Double)
    case ground

    init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let value = try? container.decode(Double.self) {
            self = .altitude(value)
        } else if let text = try? container.decode(String.self) {
            if text.lowercased() == "ground" {
                self = .ground
            } else if let value = Double(text) {
                self = .altitude(value)
            } else {
                throw DecodingError.dataCorruptedError(
                    in: container,
                    debugDescription: "Expected numeric altitude or ground",
                )
            }
        } else {
            throw DecodingError.typeMismatch(
                Double.self,
                DecodingError.Context(
                    codingPath: decoder.codingPath,
                    debugDescription: "Expected numeric altitude or ground",
                ),
            )
        }
    }
}

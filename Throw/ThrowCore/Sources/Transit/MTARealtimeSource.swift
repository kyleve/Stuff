import Foundation
import SwiftProtobuf

public protocol TransitObservationSource: Sendable {
    var partitionIDs: [TransitFeedPartitionID] { get }

    func snapshot(
        for partitionID: TransitFeedPartitionID,
        fetchedAt: Date,
    ) async throws -> TransitPartitionSnapshot
}

public struct MTARealtimeSource: TransitObservationSource {
    private struct Partition {
        let id: TransitFeedPartitionID
        let url: URL
    }

    private struct DecodedPrediction {
        let sequence: UInt32?
        let value: TransitStopTimePrediction
    }

    private static let agencyID = TransitAgencyID.mtaNewYorkCityTransit
    private static let serviceTimeZone: TimeZone = {
        guard let value = TimeZone(identifier: "America/New_York") else {
            preconditionFailure("The system must provide the IANA New York time zone")
        }
        return value
    }()

    private static let partitions: [Partition] = [
        partition("numbered", suffix: "gtfs"),
        partition("ace", suffix: "gtfs-ace"),
        partition("bdfm", suffix: "gtfs-bdfm"),
        partition("g", suffix: "gtfs-g"),
        partition("jz", suffix: "gtfs-jz"),
        partition("l", suffix: "gtfs-l"),
        partition("nqrw", suffix: "gtfs-nqrw"),
        partition("si", suffix: "gtfs-si"),
    ]

    private let transport: any HTTPTransport

    public init(transport: any HTTPTransport) {
        self.transport = transport
    }

    public var partitionIDs: [TransitFeedPartitionID] {
        Self.partitions.map(\.id)
    }

    public func snapshot(
        for partitionID: TransitFeedPartitionID,
        fetchedAt: Date,
    ) async throws -> TransitPartitionSnapshot {
        guard let partition = Self.partitions.first(where: { $0.id == partitionID }) else {
            throw TransitDataError.unavailable
        }
        let response = try await transport.response(for: HTTPRequest(
            method: .get,
            url: partition.url,
            headers: [.accept: "application/x-protobuf"],
            timeoutSeconds: 8,
        ))
        guard response.statusCode == 200 else {
            throw TransitDataError.server(statusCode: response.statusCode)
        }
        return try Self.decode(
            response.data,
            partitionID: partitionID,
            fetchedAt: fetchedAt,
        )
    }

    static func decode(
        _ data: Data,
        partitionID: TransitFeedPartitionID,
        fetchedAt: Date,
    ) throws -> TransitPartitionSnapshot {
        let feed: TransitRealtime_FeedMessage
        do {
            feed = try TransitRealtime_FeedMessage(
                serializedBytes: data,
                extensions: TransitRealtime_Gtfs_u45Realtime_u45Nyct_Extensions,
            )
        } catch {
            throw TransitDataError.invalidRealtime
        }
        guard feed.hasHeader,
              feed.header.incrementality == .fullDataset,
              feed.header.hasTimestamp
        else {
            throw TransitDataError.invalidRealtime
        }
        let generatedAt = Date(timeIntervalSince1970: TimeInterval(feed.header.timestamp))
        guard generatedAt.timeIntervalSince1970.isFinite else {
            throw TransitDataError.invalidRealtime
        }

        let runs = feed.entity.compactMap { entity -> TransitRunObservation? in
            guard entity.hasTripUpdate else { return nil }
            let update = entity.tripUpdate
            let descriptor = update.trip
            guard descriptor.hasRouteID,
                  descriptor.scheduleRelationship != .canceled,
                  let routeID = TransitRouteID(
                      agencyID: Self.agencyID,
                      rawValue: descriptor.routeID,
                  ),
                  descriptor.hasTransitRealtime_nyctTripDescriptor
            else { return nil }
            let nyct = descriptor.TransitRealtime_nyctTripDescriptor
            guard nyct.hasIsAssigned, nyct.isAssigned else { return nil }

            let serviceDate = descriptor.hasStartDate
                ? descriptor.startDate
                : Self.serviceDate(for: generatedAt)
            let stableRunValue: String
            if nyct.hasTrainID, nyct.trainID.trimmingCharacters(in: .whitespaces).isEmpty == false {
                stableRunValue = nyct.trainID.trimmingCharacters(in: .whitespaces)
            } else if descriptor.hasTripID {
                stableRunValue = [descriptor.tripID, descriptor.startTime]
                    .filter { $0.isEmpty == false }
                    .joined(separator: "/")
            } else {
                return nil
            }
            guard let runID = TransitRunID(
                agencyID: Self.agencyID,
                partitionID: partitionID,
                serviceDate: serviceDate,
                stableRunValue: stableRunValue,
            ) else { return nil }

            let predictions = update.stopTimeUpdate
                .compactMap { stop -> DecodedPrediction? in
                    guard stop.hasStopID,
                          stop.scheduleRelationship != .skipped,
                          let stopID = TransitStopID(
                              agencyID: Self.agencyID,
                              rawValue: stop.stopID,
                          )
                    else { return nil }
                    return DecodedPrediction(
                        sequence: stop.hasStopSequence ? stop.stopSequence : nil,
                        value: TransitStopTimePrediction(
                            stopID: stopID,
                            arrival: Self.date(from: stop.arrival, isPresent: stop.hasArrival),
                            departure: Self.date(
                                from: stop.departure,
                                isPresent: stop.hasDeparture,
                            ),
                        ),
                    )
                }
                .sorted { lhs, rhs in
                    switch (lhs.sequence, rhs.sequence) {
                        case let (left?, right?): left < right
                        case (_?, nil): true
                        case (nil, _?): false
                        case (nil, nil): false
                    }
                }
                .map(\.value)
            guard predictions.isEmpty == false else { return nil }

            let direction: Int? = if descriptor.hasDirectionID {
                Int(descriptor.directionID)
            } else if nyct.hasDirection {
                switch nyct.direction {
                    case .north, .east: 0
                    case .south, .west: 1
                }
            } else {
                nil
            }
            if let direction, (0 ... 1).contains(direction) == false { return nil }
            let tripID = descriptor.hasTripID
                ? TransitTripID(agencyID: Self.agencyID, rawValue: descriptor.tripID)
                : nil
            return TransitRunObservation(
                id: runID,
                tripID: tripID,
                routeID: routeID,
                direction: direction,
                observedAt: update.hasTimestamp
                    ? Date(timeIntervalSince1970: TimeInterval(update.timestamp))
                    : generatedAt,
                upcomingStops: predictions,
            )
        }

        return TransitPartitionSnapshot(
            partitionID: partitionID,
            generatedAt: generatedAt,
            fetchedAt: fetchedAt,
            runs: runs,
        )
    }

    private static func partition(_ id: String, suffix: String) -> Partition {
        guard let partitionID = TransitFeedPartitionID(rawValue: id) else {
            preconditionFailure("Bundled MTA partition identifiers must be valid")
        }
        let encodedPath = "nyct%2F\(suffix)"
        guard let url = URL(
            string: "https://api-endpoint.mta.info/Dataservice/mtagtfsfeeds/\(encodedPath)",
        ) else {
            preconditionFailure("Bundled MTA feed URLs must be valid")
        }
        return Partition(id: partitionID, url: url)
    }

    private static func date(
        from event: TransitRealtime_TripUpdate.StopTimeEvent,
        isPresent: Bool,
    ) -> Date? {
        guard isPresent, event.hasTime else { return nil }
        return Date(timeIntervalSince1970: TimeInterval(event.time))
    }

    private static func serviceDate(for date: Date) -> String {
        let calendar = Calendar(identifier: .gregorian)
        let components = calendar.dateComponents(
            in: serviceTimeZone,
            from: date,
        )
        return String(
            format: "%04d%02d%02d",
            components.year ?? 1970,
            components.month ?? 1,
            components.day ?? 1,
        )
    }
}

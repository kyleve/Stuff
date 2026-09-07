import Foundation
import SwiftProtobuf
import Testing
@testable import ThrowCore

struct MTARealtimeSourceTests {
    @Test func decoderKeepsOnlyAssignedPhysicalRuns() throws {
        let data = try feedData(isAssigned: true)
        let partition = try #require(TransitFeedPartitionID(rawValue: "ace"))
        let snapshot = try MTARealtimeSource.decode(
            data,
            partitionID: partition,
            fetchedAt: ThrowCoreFixture.date,
        )
        let run = try #require(snapshot.runs.first)
        #expect(run.routeID.rawValue == "A")
        #expect(run.id.stableRunValue == "A-101")
        #expect(run.upcomingStops.first?.stopID.rawValue == "A02N")
    }

    @Test func decoderDropsUnassignedTrips() throws {
        let partition = try #require(TransitFeedPartitionID(rawValue: "ace"))
        let snapshot = try MTARealtimeSource.decode(
            feedData(isAssigned: false),
            partitionID: partition,
            fetchedAt: ThrowCoreFixture.date,
        )
        #expect(snapshot.runs.isEmpty)
    }

    @Test func decoderDropsCanceledTrips() throws {
        let partition = try #require(TransitFeedPartitionID(rawValue: "ace"))
        let snapshot = try MTARealtimeSource.decode(
            feedData(isAssigned: true, isCanceled: true),
            partitionID: partition,
            fetchedAt: ThrowCoreFixture.date,
        )
        #expect(snapshot.runs.isEmpty)
    }

    @Test func decoderOrdersPredictionsByStopSequence() throws {
        let partition = try #require(TransitFeedPartitionID(rawValue: "ace"))
        let snapshot = try MTARealtimeSource.decode(
            feedData(isAssigned: true, reversesStopOrder: true),
            partitionID: partition,
            fetchedAt: ThrowCoreFixture.date,
        )
        #expect(snapshot.runs.first?.upcomingStops.map(\.stopID.rawValue) == ["A02N", "A03N"])
    }

    private func feedData(
        isAssigned: Bool,
        isCanceled: Bool = false,
        reversesStopOrder: Bool = false,
    ) throws -> Data {
        var header = TransitRealtime_FeedHeader()
        header.gtfsRealtimeVersion = "2.0"
        header.incrementality = .fullDataset
        header.timestamp = UInt64(ThrowCoreFixture.date.timeIntervalSince1970)

        var nyct = TransitRealtime_NyctTripDescriptor()
        nyct.trainID = "A-101"
        nyct.isAssigned = isAssigned
        nyct.direction = .north

        var descriptor = TransitRealtime_TripDescriptor()
        descriptor.tripID = "trip-A"
        descriptor.routeID = "A"
        descriptor.startDate = "20231114"
        if isCanceled { descriptor.scheduleRelationship = .canceled }
        descriptor.TransitRealtime_nyctTripDescriptor = nyct

        var arrival = TransitRealtime_TripUpdate.StopTimeEvent()
        arrival.time = Int64(ThrowCoreFixture.date.addingTimeInterval(60).timeIntervalSince1970)
        var stop = TransitRealtime_TripUpdate.StopTimeUpdate()
        stop.stopID = "A02N"
        stop.stopSequence = 2
        stop.arrival = arrival
        var laterStop = TransitRealtime_TripUpdate.StopTimeUpdate()
        laterStop.stopID = "A03N"
        laterStop.stopSequence = 3
        laterStop.arrival = arrival

        var update = TransitRealtime_TripUpdate()
        update.trip = descriptor
        update.timestamp = UInt64(ThrowCoreFixture.date.timeIntervalSince1970)
        update.stopTimeUpdate = reversesStopOrder ? [laterStop, stop] : [stop]

        var entity = TransitRealtime_FeedEntity()
        entity.id = "entity-A"
        entity.tripUpdate = update
        var feed = TransitRealtime_FeedMessage()
        feed.header = header
        feed.entity = [entity]
        return try feed.serializedData()
    }
}

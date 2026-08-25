import Foundation
import Testing
@testable import ThrowCore

struct GeographyLayerRuntimeTests {
    @Test func decoderRestoresDeltaCoordinatesAndBoundaryKind() async throws {
        let data = Data(
            """
            {
              "version": 2,
              "coordinateScale": 100,
              "sources": [{"id":"fixture","name":"Fixture","release":"1","scale":"fixture"}],
              "paths": [{
                "kind":"disputed-boundary",
                "detailLevel":"wide",
                "bounds":[100,180,110,200],
                "coordinates":[100,200,10,-20]
              }]
            }
            """.utf8,
        )

        let lines = try await GeographyArchiveDecoder.decode(data)
        let line = try #require(lines.first)

        #expect(line.kind == .disputedBoundary)
        #expect(line.detailLevel == .wide)
        #expect(line.coordinates.count == 2)
        #expect(line.coordinates[0].latitude == 1)
        #expect(line.coordinates[0].longitude == 2)
        #expect(line.coordinates[1].latitude == 1.1)
        #expect(line.coordinates[1].longitude == 1.8)
    }

    @Test func decoderValidatesSourcesAndDecodesLODsAndNewLineKinds() async throws {
        let data = Data(
            """
            {
              "version": 2,
              "coordinateScale": 100,
              "sources": [
                {"id":"natural-earth","name":"Natural Earth Vector","release":"5.1.2","scale":"1:10m"},
                {"id":"us-census","name":"US Census Bureau","release":"2025","scale":"TIGER/Line"}
              ],
              "paths": [
                {"kind":"county-boundary","detailLevel":"wide","bounds":[100,180,110,200],"coordinates":[100,200,10,-20]},
                {"kind":"primary-road","detailLevel":"standard","bounds":[100,180,110,200],"coordinates":[100,200,10,-20]},
                {"kind":"river","detailLevel":"local","bounds":[100,180,110,200],"coordinates":[100,200,10,-20],"ignored":"additive"}
              ],
              "ignored": true
            }
            """.utf8,
        )

        let lines = try await GeographyArchiveDecoder.decode(data)

        #expect(lines.map(\.kind) == [.countyBoundary, .primaryRoad, .river])
        #expect(lines.map(\.detailLevel) == [.wide, .standard, .local])
    }

    @Test func versionTwoDecoderRejectsDuplicateSourceIDs() async {
        let data = Data(
            """
            {"version":2,"coordinateScale":100,"sources":[{"id":"source","name":"One","release":"1","scale":"one"},{"id":"source","name":"Two","release":"2","scale":"two"}],"paths":[]}
            """.utf8,
        )

        await #expect(throws: GeographyDataError.invalidArchive) {
            try await GeographyArchiveDecoder.decode(data)
        }
    }

    @Test(arguments: ["", "Natural-Earth", "-natural-earth", "natural--earth", "natural_earth"])
    func decoderRejectsAnUnstableSourceID(id: String) async {
        let prefix = #"{"version":2,"coordinateScale":100,"sources":[{"id":""#
        let suffix = #"","name":"Fixture","release":"1","scale":"fixture"}],"paths":[]}"#
        let data = Data((prefix + id + suffix).utf8)

        await #expect(throws: GeographyDataError.invalidArchive) {
            try await GeographyArchiveDecoder.decode(data)
        }
    }

    @Test func decoderRejectsTheReplacedVersionOneSchema() async {
        let data = Data(
            """
            {"version":1,"coordinateScale":100,"source":{"name":"Fixture","release":"1","scale":"fixture"},"paths":[]}
            """.utf8,
        )

        await #expect(throws: GeographyDataError.invalidArchive) {
            try await GeographyArchiveDecoder.decode(data)
        }
    }

    @Test func decoderRejectsAnOddDeltaArray() async {
        let data = Data(
            """
            {"version":2,"coordinateScale":100,"sources":[{"id":"fixture","name":"Fixture","release":"1","scale":"fixture"}],"paths":[{"kind":"river","detailLevel":"wide","bounds":[0,0,1,1],"coordinates":[0,0,1,1,2]}]}
            """.utf8,
        )

        await #expect(throws: GeographyDataError.invalidArchive) {
            try await GeographyArchiveDecoder.decode(data)
        }
    }

    @Test func decoderRejectsCoordinatesOutsideStoredBounds() async {
        let data = Data(
            """
            {"version":2,"coordinateScale":100,"sources":[{"id":"fixture","name":"Fixture","release":"1","scale":"fixture"}],"paths":[{"kind":"river","detailLevel":"wide","bounds":[0,0,1,1],"coordinates":[0,0,200,0]}]}
            """.utf8,
        )

        await #expect(throws: GeographyDataError.invalidArchive) {
            try await GeographyArchiveDecoder.decode(data)
        }
    }

    @Test func decoderHonorsCancellationBeforeStartingWork() async {
        let gate = GeographyDecoderCancellationGate()
        let data = Data(
            """
            {"version":2,"coordinateScale":100,"sources":[{"id":"fixture","name":"Fixture","release":"1","scale":"fixture"}],"paths":[]}
            """.utf8,
        )
        let task = Task {
            await gate.wait()
            return try await GeographyArchiveDecoder.decode(data)
        }
        await gate.waitUntilSuspended()

        task.cancel()
        await gate.release()

        do {
            _ = try await task.value
            Issue.record("Expected decoding to stop after cancellation.")
        } catch is CancellationError {
            // Expected.
        } catch {
            Issue.record("Expected CancellationError, received \(error).")
        }
    }

    @Test func bundledArchiveContainsEveryLineKindAndProjectsLocalContext() async throws {
        let runtime = GeographyLayerRuntime(dataSource: BundledGeographyDataSource())
        let frame = try await runtime.frame(for: GeographyLayerInput())

        #expect(frame.layerID == .geography)
        #expect(frame.marks.isEmpty)
        #expect(frame.geographicLines.count == 38483)
        #expect(Set(frame.geographicLines.map(\.kind)) == Set(GeographyLineKind.allCases))
        #expect(
            Set(frame.geographicLines.map(\.detailLevel)) == Set(GeographyDetailLevel.allCases),
        )
        let observer = try ObserverPosition(
            coordinate: GeoCoordinate(latitude: 37.7749, longitude: -122.4194),
            altitude: Altitude(feet: 0),
        )

        let segments = try ProjectionEngine().geographySegments(
            lines: frame.geographicLines,
            observer: observer,
            viewport: .map(MapViewport(radius: NauticalMiles(value: 50))),
            calibration: .defaultValue,
            geometry: ProjectionGeometry(width: 960, height: 540),
        )

        #expect(segments.count >= 50)
        let kinds = Set(segments.map(\.kind))
        #expect(kinds.contains(.coastline))
        #expect(kinds.contains(.primaryRoad))
    }

    @Test func bundledResourcesContainOnlyTheCurrentGeographyArchive() {
        #expect(
            Bundle.module.url(forResource: "geography-v2", withExtension: "json") != nil,
        )
        #expect(
            Bundle.module.url(forResource: "geography-v1", withExtension: "json") == nil,
        )
    }
}

private actor GeographyDecoderCancellationGate {
    private var continuation: CheckedContinuation<Void, Never>?

    func wait() async {
        await withCheckedContinuation { continuation in
            self.continuation = continuation
        }
    }

    func waitUntilSuspended() async {
        while continuation == nil {
            await Task.yield()
        }
    }

    func release() {
        continuation?.resume()
        continuation = nil
    }
}

import Foundation
import Testing
@testable import ThrowCore

struct GeographyLayerRuntimeTests {
    @Test func decoderRestoresDeltaCoordinatesAndBoundaryKind() async throws {
        let data = Data(
            """
            {
              "version": 1,
              "coordinateScale": 100,
              "source": {"name":"Fixture","release":"1","scale":"fixture"},
              "paths": [{
                "kind":"disputed-boundary",
                "minimumZoomTenths":45,
                "scaleRank":2,
                "bounds":[100,180,110,200],
                "coordinates":[100,200,10,-20]
              }]
            }
            """.utf8,
        )

        let lines = try await GeographyArchiveDecoder.decode(data)
        let line = try #require(lines.first)

        #expect(line.kind == .disputedBoundary)
        #expect(line.minimumZoomTenths == 45)
        #expect(line.scaleRank == 2)
        #expect(line.coordinates.count == 2)
        #expect(line.coordinates[0].latitude == 1)
        #expect(line.coordinates[0].longitude == 2)
        #expect(line.coordinates[1].latitude == 1.1)
        #expect(line.coordinates[1].longitude == 1.8)
    }

    @Test func decoderRejectsAnOddDeltaArray() async {
        let data = Data(
            """
            {"version":1,"coordinateScale":100,"source":{"name":"Fixture","release":"1","scale":"fixture"},"paths":[{"kind":"river","minimumZoomTenths":0,"scaleRank":0,"bounds":[0,0,1,1],"coordinates":[0,0,1,1,2]}]}
            """.utf8,
        )

        await #expect(throws: GeographyDataError.invalidArchive) {
            try await GeographyArchiveDecoder.decode(data)
        }
    }

    @Test func decoderRejectsCoordinatesOutsideStoredBounds() async {
        let data = Data(
            """
            {"version":1,"coordinateScale":100,"source":{"name":"Fixture","release":"1","scale":"fixture"},"paths":[{"kind":"river","minimumZoomTenths":0,"scaleRank":0,"bounds":[0,0,1,1],"coordinates":[0,0,200,0]}]}
            """.utf8,
        )

        await #expect(throws: GeographyDataError.invalidArchive) {
            try await GeographyArchiveDecoder.decode(data)
        }
    }

    @Test func bundledArchiveContainsEverySemanticLineKind() async throws {
        let runtime = GeographyLayerRuntime(dataSource: BundledGeographyDataSource())
        let frame = try await runtime.frame(for: GeographyLayerInput())

        #expect(frame.layerID == .geography)
        #expect(frame.marks.isEmpty)
        #expect(frame.geographicLines.count == 3774)
        #expect(Set(frame.geographicLines.map(\.kind)) == Set(GeographyLineKind.allCases))
    }
}

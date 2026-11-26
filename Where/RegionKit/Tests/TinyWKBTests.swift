import Foundation
@testable import RegionKit
import Testing

struct TinyWKBTests {
    /// Two polygons. Coordinates are seven-decimal integer deltas, including
    /// the first vertex of the second polygon relative to the last of the first.
    private let fixture: [UInt8] = [
        0xE6,
        0,
        2,
        1,
        3,
        0,
        0,
        4,
        0,
        3,
        4,
        1,
        3,
        5,
        3,
        2,
        0,
        1,
        2,
    ]

    @Test func decodesTheDocumentedDeltaStreamAndClosesEachRing() throws {
        let polygons = try TinyWKB.polygons(in: Data(fixture))
        let origin = Coordinate(latitude: 0, longitude: 0)
        let west = Coordinate(latitude: 0, longitude: -0.0000003)
        #expect(polygons.count == 2)
        #expect(polygons[0].vertices == [
            origin,
            Coordinate(latitude: 0, longitude: 0.0000002),
            Coordinate(latitude: 0.0000002, longitude: 0),
            origin,
        ])
        #expect(polygons[1].vertices == [
            west,
            Coordinate(latitude: 0, longitude: -0.0000002),
            Coordinate(latitude: 0.0000001, longitude: -0.0000003),
            west,
        ])
    }

    @Test func rejectsTruncationTrailingBytesAndUnsupportedHeaders() {
        for malformed in [
            Array(fixture.dropLast()),
            fixture + [0],
            [0xE6, 2, 1],
            [0x03, 0, 1],
            [0xE6, 0, 0x80, 0x80, 0x80, 0x80, 0x80, 1],
        ] {
            #expect(throws: CocoaError.self) { try TinyWKB.polygons(in: Data(malformed)) }
        }
    }
}

@testable import RegionKit
import Testing

struct LongitudeSpanTests {
    @Test func emptyIsNil() {
        #expect(LongitudeSpan.enclosing([] as [Double]) == nil)
    }

    @Test func singleLongitudeHasZeroWidth() throws {
        let span = try #require(LongitudeSpan.enclosing([42.0]))
        #expect(span.center == 42)
        #expect(span.degrees == 0)
    }

    @Test func westernClusterUsesPlainMinMax() throws {
        let span = try #require(LongitudeSpan.enclosing([-100, -90, -80]))
        #expect(span.center == -90)
        #expect(span.degrees == 20)
    }

    @Test func orderOfInputDoesNotMatter() throws {
        let ascending = try #require(LongitudeSpan.enclosing([-100, -90, -80]))
        let shuffled = try #require(LongitudeSpan.enclosing([-80, -100, -90]))
        #expect(ascending == shuffled)
    }

    /// A cluster straddling ±180° frames as the short arc across the
    /// antimeridian (centered on 180°), not the long way around.
    @Test func antimeridianClusterFramesTheShortArc() throws {
        let span = try #require(LongitudeSpan.enclosing([170, 175, -175, -170]))
        #expect(span.center == 180)
        #expect(span.degrees == 20)
    }

    /// Alaska's shape: longitudes from ~+172° east across 180° to ~−130°.
    /// The tight arc (~58° wide, centered out near the Aleutians) is the
    /// whole point — a naive `max − min` would report ~358°.
    @Test func alaskaShapedSpanIsTightNotGlobal() throws {
        let span = try #require(LongitudeSpan.enclosing([172, 179, -179, -130]))
        #expect(span.degrees == 58)
        #expect(span.center == -159)

        let naive = 179.0 - -179.0
        #expect(span.degrees < naive)
        #expect(span.center >= -180 && span.center <= 180)
    }

    @Test func widestGapDeterminesTheEnclosingArc() throws {
        // Occupied near 0° and near 90°; the widest empty gap is the wrap
        // from 90° back to −10°, so the arc runs −10°…90°.
        let span = try #require(LongitudeSpan.enclosing([-10, 0, 10, 80, 90]))
        #expect(span.center == 40)
        #expect(span.degrees == 100)
    }
}

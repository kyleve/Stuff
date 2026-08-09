import PatchlightCore
import Testing

struct SnapshotAnnotationV1Tests {
    @Test func markerRoundTripsAsBase64URLJSON() throws {
        let annotation = try SnapshotAnnotationV1(
            path: "Feature/Tests/Snapshots/card.png",
            target: .head,
            blobOID: PatchlightCoreTestSupport.objectID(),
            rectangle: NormalizedRectangle(x: 0.1, y: 0.2, width: 0.3, height: 0.4),
            sourceWidth: 1200,
            sourceHeight: 800,
            tag: .problem,
        )
        let comment = try "The title overlaps here.\n\n\(annotation.marker())"
        #expect(try SnapshotAnnotationV1.parseMarker(in: comment) == annotation)
    }

    @Test func ordinaryAndUnknownVersionCommentsStayOrdinary() throws {
        #expect(try SnapshotAnnotationV1.parseMarker(in: "Looks good") == nil)
        #expect(
            try SnapshotAnnotationV1.parseMarker(
                in: "<!-- patchlight-snapshot:v2:opaque -->",
            ) == nil,
        )
    }

    @Test func rejectsGeometryOutsideTheImage() {
        #expect(throws: SnapshotAnnotationError.invalidRectangle) {
            try NormalizedRectangle(x: 0.9, y: 0, width: 0.2, height: 1)
        }
    }
}

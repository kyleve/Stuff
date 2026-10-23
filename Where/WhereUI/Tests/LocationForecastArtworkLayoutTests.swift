import CoreGraphics
import Testing
@testable import WhereUI

struct LocationForecastArtworkLayoutTests {
    @Test(arguments: [1, 2, 3, 7, 20, 56])
    func everyRegionFitsWithoutOverlap(count: Int) {
        let size = CGSize(width: 180, height: 72)
        let bounds = CGRect(origin: .zero, size: size)
        let frames = LocationForecastArtworkLayout.frames(count: count, in: size, gap: 8)
        #expect(frames.count == count)
        for (index, frame) in frames.enumerated() {
            #expect(bounds.contains(frame))
            #expect(frame.width > 0 && frame.height > 0)
            for other in frames.dropFirst(index + 1) {
                #expect(!frame.intersects(other))
            }
        }
    }

    @Test func emptyOrUnmeasuredArtworkHasNoCells() {
        #expect(LocationForecastArtworkLayout.frames(
            count: 0,
            in: CGSize(width: 180, height: 72),
            gap: 8,
        )
        .isEmpty)
        #expect(LocationForecastArtworkLayout.frames(count: 3, in: .zero, gap: 8).isEmpty)
    }

    @Test func singleRegionIsCentered() throws {
        let frame = try #require(LocationForecastArtworkLayout.frames(
            count: 1,
            in: CGSize(width: 180, height: 72),
            gap: 8,
        ).first)
        #expect(frame.midX == 90)
        #expect(frame.midY == 36)
    }
}

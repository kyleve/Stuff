import Testing

@testable import PhotoFramer

@Suite
struct FrameSizeTests {

    @Test func allSizesHavePositiveAspectRatios() {
        for size in FrameSize.allSizes {
            #expect(size.aspectRatio > 0)
        }
    }

    @Test func printSizesCount() {
        #expect(FrameSize.sizes(for: .print).count == 4)
    }

    @Test func socialSizesCount() {
        #expect(FrameSize.sizes(for: .social).count == 4)
    }

    @Test func totalSizesCount() {
        #expect(FrameSize.allSizes.count == 8)
    }

    @Test func squareAspectRatioIsOne() {
        let square = FrameSize.allSizes.first { $0.id == "1:1" }!
        #expect(square.aspectRatio == 1.0)
    }

    @Test func landscapeAspectRatioGreaterThanOne() {
        let landscape = FrameSize.allSizes.first { $0.id == "16:9" }!
        #expect(landscape.aspectRatio > 1.0)
    }

    @Test func portraitAspectRatioLessThanOne() {
        let portrait = FrameSize.allSizes.first { $0.id == "9:16" }!
        #expect(portrait.aspectRatio < 1.0)
    }

    @Test func allIdsAreUnique() {
        let ids = FrameSize.allSizes.map(\.id)
        #expect(Set(ids).count == ids.count)
    }
}

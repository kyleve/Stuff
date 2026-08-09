import CoreGraphics
import Foundation
import ImageDiffKit
import Testing
import UIKit

struct ImageDiffEngineTests {
    private let engine = ImageDiffEngine()

    @Test func identicalImagesHaveNoChangedBounds() throws {
        let image = try #require(imageData(size: CGSize(width: 8, height: 6)))
        let result = try engine.compare(base: image, head: image, options: .exact)
        guard case let .comparable(metrics, heatmap) = result else {
            Issue.record("Expected same-sized images to be comparable")
            return
        }

        #expect(metrics.dimensions == ImageDimensions(width: 8, height: 6))
        #expect(metrics.changedPixels == 0)
        #expect(metrics.changedFraction == 0)
        #expect(metrics.maximumChannelDelta == 0)
        #expect(metrics.changedBounds == nil)
        #expect(heatmap == nil)
    }

    @Test func localizesAChangedRegionAndGeneratesAHeatmap() throws {
        let size = CGSize(width: 20, height: 20)
        let base = try #require(imageData(size: size))
        let head = try #require(
            imageData(size: size, patch: CGRect(x: 3, y: 2, width: 5, height: 4)),
        )
        let result = try engine.compare(base: base, head: head, options: .exactWithHeatmap)
        guard case let .comparable(metrics, heatmap) = result else {
            Issue.record("Expected same-sized images to be comparable")
            return
        }

        #expect(metrics.changedPixels == 20)
        #expect(metrics.changedFraction == 0.05)
        #expect(metrics.maximumChannelDelta == 255)
        #expect(metrics.changedBounds == CGRect(x: 3, y: 2, width: 5, height: 4))
        let heatmapData = try #require(heatmap)
        #expect(UIImage(data: heatmapData)?.size == size)
    }

    @Test func toleranceSuppressesSmallDeltasWithoutLosingMaximumDelta() throws {
        let base = try #require(imageData(color: UIColor(white: 0.5, alpha: 1)))
        let head = try #require(imageData(color: UIColor(white: 0.51, alpha: 1)))
        let options = ImageDiffOptions(channelTolerance: 3, generatesHeatmap: false)
        let result = try engine.compare(base: base, head: head, options: options)
        guard case let .comparable(metrics, _) = result else {
            Issue.record("Expected same-sized images to be comparable")
            return
        }

        #expect(metrics.changedPixels == 0)
        #expect(metrics.maximumChannelDelta > 0)
        #expect(metrics.maximumChannelDelta <= 3)
    }

    @Test func reportsDimensionMismatchWithoutPretendingToComparePixels() throws {
        let base = try #require(imageData(size: CGSize(width: 4, height: 4)))
        let head = try #require(imageData(size: CGSize(width: 8, height: 4)))
        #expect(
            try engine.compare(base: base, head: head, options: .exact) == .dimensionMismatch(
                base: ImageDimensions(width: 4, height: 4),
                head: ImageDimensions(width: 8, height: 4),
            ),
        )
    }

    @Test func invalidDataSurfacesTheResponsibleSide() throws {
        let valid = try #require(imageData())
        #expect(throws: ImageDiffError.undecodable(.base)) {
            try engine.compare(base: Data("not an image".utf8), head: valid, options: .exact)
        }
        #expect(throws: ImageDiffError.undecodable(.head)) {
            try engine.compare(base: valid, head: Data(), options: .exact)
        }
    }

    private func imageData(
        color: UIColor = .black,
        size: CGSize = CGSize(width: 8, height: 8),
        patch: CGRect? = nil,
    ) -> Data? {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.preferredRange = .standard
        return UIGraphicsImageRenderer(size: size, format: format).image { context in
            color.setFill()
            context.fill(CGRect(origin: .zero, size: size))
            if let patch {
                UIColor.white.setFill()
                context.fill(patch)
            }
        }.pngData()
    }
}

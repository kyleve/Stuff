import CoreGraphics
import Testing
@testable import WhereUI

struct AppIconLayoutTests {
    @Test func gridKeepsAtLeastTwoColumnsOnNarrowWidths() {
        let metrics = AppIconLayout.gridMetrics(containerWidth: 320)
        #expect(metrics.columnCount == 2)
        #expect(metrics.iconSize > 0)
    }

    @Test(arguments: stride(from: 200.0, through: 2000.0, by: 50.0).map { CGFloat($0) })
    func gridIconNeverExceedsTheMaximum(width: CGFloat) {
        let metrics = AppIconLayout.gridMetrics(containerWidth: width)
        #expect(metrics.iconSize <= UIConstants.Size.appIconGridMax)
        #expect(metrics.columnCount >= 2)
    }

    @Test func gridAddsColumnsAsTheContainerGrows() {
        let phone = AppIconLayout.gridMetrics(containerWidth: 393)
        let pad = AppIconLayout.gridMetrics(containerWidth: 1024)
        #expect(phone.columnCount == 2)
        #expect(pad.columnCount > phone.columnCount)
    }

    @Test func gridIconGrowsWithWidthUntilItCaps() {
        let narrow = AppIconLayout.gridMetrics(containerWidth: 360)
        let wide = AppIconLayout.gridMetrics(containerWidth: 430)
        #expect(wide.iconSize >= narrow.iconSize)
    }

    @Test func gridHandlesAZeroWidthWithoutNegativeSizes() {
        let metrics = AppIconLayout.gridMetrics(containerWidth: 0)
        #expect(metrics.columnCount == 2)
        #expect(metrics.iconSize == 0)
    }

    @Test func previewLargeClampsToTheMaximumOnHugeContainers() {
        let metrics = AppIconLayout.previewMetrics(containerSize: CGSize(width: 4000, height: 4000))
        #expect(metrics.large == UIConstants.Size.appIconPreviewLargeMax)
        #expect(metrics.small < metrics.large)
        #expect(metrics.small > 0)
    }

    @Test func previewScalesDownForSmallContainers() {
        let big = AppIconLayout.previewMetrics(containerSize: CGSize(width: 4000, height: 4000))
        let small = AppIconLayout.previewMetrics(containerSize: CGSize(width: 320, height: 480))
        #expect(small.large < big.large)
        #expect(small.large > 0)
    }

    @Test func previewIsBoundedByTheShorterDimension() {
        // A short, wide container should size the large preview off the height.
        let metrics = AppIconLayout.previewMetrics(containerSize: CGSize(width: 4000, height: 400))
        #expect(metrics.large <= 400 * 0.4 + 0.001)
    }

    @Test(arguments: stride(from: 200.0, through: 1400.0, by: 100.0).map { CGFloat($0) })
    func previewLargeAlwaysExceedsSmallAndStaysCapped(side: CGFloat) {
        let metrics = AppIconLayout.previewMetrics(containerSize: CGSize(width: side, height: side))
        #expect(metrics.large > metrics.small)
        #expect(metrics.large <= UIConstants.Size.appIconPreviewLargeMax)
    }
}

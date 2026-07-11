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
        #expect(metrics.iconSize <= WhereStylesheet.default.size.appIconGridMax)
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

    @Test func previewIconClampsToTheMaximumOnHugeContainers() {
        let size = AppIconLayout.previewIconSize(containerSize: CGSize(width: 4000, height: 4000))
        #expect(size == WhereStylesheet.default.size.appIconPreviewLargeMax)
    }

    @Test func previewIconScalesDownForSmallContainers() {
        let big = AppIconLayout.previewIconSize(containerSize: CGSize(width: 4000, height: 4000))
        let small = AppIconLayout.previewIconSize(containerSize: CGSize(width: 320, height: 480))
        #expect(small < big)
        #expect(small > 0)
    }

    @Test func previewIconIsBoundedByTheShorterDimension() {
        // A short, wide container should size the preview icon off the height.
        let size = AppIconLayout.previewIconSize(containerSize: CGSize(width: 4000, height: 400))
        #expect(size <= 400 * 0.3 + 0.001)
    }

    @Test(arguments: stride(from: 200.0, through: 1400.0, by: 100.0).map { CGFloat($0) })
    func previewIconStaysCappedAndPositive(side: CGFloat) {
        let size = AppIconLayout.previewIconSize(containerSize: CGSize(width: side, height: side))
        #expect(size > 0)
        #expect(size <= WhereStylesheet.default.size.appIconPreviewLargeMax)
    }
}

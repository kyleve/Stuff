import CoreGraphics
import Testing
@testable import WhereUI

private let style = WhereStylesheet.AppIconStyle.standard

struct AppIconLayoutTests {
    @Test func gridKeepsAtLeastTwoColumnsOnNarrowWidths() {
        let metrics = AppIconLayout.gridMetrics(containerWidth: 320, style: style)
        #expect(metrics.columnCount == 2)
        #expect(metrics.iconSize > 0)
    }

    @Test(arguments: stride(from: 200.0, through: 2000.0, by: 50.0).map { CGFloat($0) })
    func gridIconNeverExceedsTheMaximum(width: CGFloat) {
        let metrics = AppIconLayout.gridMetrics(containerWidth: width, style: style)
        #expect(metrics.iconSize <= style.gridMax)
        #expect(metrics.columnCount >= 2)
    }

    @Test func gridAddsColumnsAsTheContainerGrows() {
        let phone = AppIconLayout.gridMetrics(containerWidth: 393, style: style)
        let pad = AppIconLayout.gridMetrics(containerWidth: 1024, style: style)
        #expect(phone.columnCount == 2)
        #expect(pad.columnCount > phone.columnCount)
    }

    @Test func gridIconGrowsWithWidthUntilItCaps() {
        let narrow = AppIconLayout.gridMetrics(containerWidth: 360, style: style)
        let wide = AppIconLayout.gridMetrics(containerWidth: 430, style: style)
        #expect(wide.iconSize >= narrow.iconSize)
    }

    @Test func gridHandlesAZeroWidthWithoutNegativeSizes() {
        let metrics = AppIconLayout.gridMetrics(containerWidth: 0, style: style)
        #expect(metrics.columnCount == 2)
        #expect(metrics.iconSize == 0)
    }

    @Test func previewIconClampsToTheMaximumOnHugeContainers() {
        let size = AppIconLayout.previewIconSize(
            containerSize: CGSize(width: 4000, height: 4000),
            style: style,
        )
        #expect(size == style.previewMax)
    }

    @Test func previewIconScalesDownForSmallContainers() {
        let big = AppIconLayout.previewIconSize(
            containerSize: CGSize(width: 4000, height: 4000),
            style: style,
        )
        let small = AppIconLayout.previewIconSize(
            containerSize: CGSize(width: 320, height: 480),
            style: style,
        )
        #expect(small < big)
        #expect(small > 0)
    }

    @Test func previewIconIsBoundedByTheShorterDimension() {
        // A short, wide container should size the preview icon off the height.
        let size = AppIconLayout.previewIconSize(
            containerSize: CGSize(width: 4000, height: 400),
            style: style,
        )
        #expect(size <= 400 * 0.3 + 0.001)
    }

    @Test(arguments: stride(from: 200.0, through: 1400.0, by: 100.0).map { CGFloat($0) })
    func previewIconStaysCappedAndPositive(side: CGFloat) {
        let size = AppIconLayout.previewIconSize(
            containerSize: CGSize(width: side, height: side),
            style: style,
        )
        #expect(size > 0)
        #expect(size <= style.previewMax)
    }
}

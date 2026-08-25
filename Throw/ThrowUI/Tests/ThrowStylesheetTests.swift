import Testing
import ThrowCore
@testable import ThrowUI

struct ThrowStylesheetTests {
    @Test func projectionLabelsStayVisuallySubordinateToMarks() {
        let projection = ThrowStylesheet.ProjectionStyle.standard

        #expect(
            projection.label.font == .system(
                size: 10,
                weight: .regular,
                design: .monospaced,
            ),
        )
        #expect((0 ..< 1).contains(projection.label.luminanceMultiplier))
        #expect(projection.label.offset > 0)
    }

    @Test func everyCuratedCarrierHasABoundedMutedAccentColor() {
        let style = ThrowStylesheet.AircraftStyle.standard

        #expect(style.brandColors.count == AirlineBrand.allCases.count)
        for color in style.brandColors.values {
            #expect((0 ... 1).contains(color.red))
            #expect((0 ... 1).contains(color.green))
            #expect((0 ... 1).contains(color.blue))
        }
    }

    @Test(arguments: GeographyLineKind.allCases)
    func everyGeographyKindHasAVisibleBoundedStyle(_ kind: GeographyLineKind) {
        let line = ThrowStylesheet.GeographyStyle.standard[kind]

        #expect(line.lineWidth > 0)
        #expect((0 ... 1).contains(line.luminance))
        #expect(line.luminance > 0)
    }

    @Test func roadsAndLocalBoundariesStaySubordinateToRegionalAnchors() {
        let style = ThrowStylesheet.GeographyStyle.standard

        #expect(style[.primaryRoad].luminance < style[.coastline].luminance)
        #expect(style[.countyBoundary].luminance < style[.regionalBoundary].luminance)
        #expect(style[.primaryRoad].lineWidth < style[.coastline].lineWidth)
    }

    @Test func uncertainAndLocalBoundariesUseDistinctPatterns() {
        let style = ThrowStylesheet.GeographyStyle.standard

        #expect(style[.disputedBoundary].dash.isEmpty == false)
        #expect(style[.countyBoundary].dash.isEmpty == false)
        #expect(style[.nationalBoundary].dash.isEmpty)
        #expect(style[.regionalBoundary].dash.isEmpty)
        #expect(style[.primaryRoad].dash.isEmpty)
    }

    @Test func localDetailDrawsBeforeStructuralAnchors() throws {
        let style = ThrowStylesheet.GeographyStyle.standard
        let order = style.renderOrder

        #expect(order.count == GeographyLineKind.allCases.count)
        #expect(Set(order) == Set(GeographyLineKind.allCases))
        let primaryRoad = try #require(order.firstIndex(of: .primaryRoad))
        let nationalBoundary = try #require(order.firstIndex(of: .nationalBoundary))
        let coastline = try #require(order.firstIndex(of: .coastline))
        #expect(primaryRoad < nationalBoundary)
        #expect(nationalBoundary < coastline)
    }
}

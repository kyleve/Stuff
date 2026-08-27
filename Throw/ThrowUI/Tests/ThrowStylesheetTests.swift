import Testing
import ThrowCore
@testable import ThrowUI

struct ThrowStylesheetTests {
    @Test func experienceTransitionsUseTheProjectorFadeToken() {
        #expect(ThrowStylesheet.ProjectionStyle.standard.experienceTransition.fadeDuration == 0.4)
    }

    @Test func transitMarksAndNetworkHaveBoundedProjectionStyles() {
        let style = ThrowStylesheet.TransitStyle.standard

        #expect(style.vehicleDiameter > 0)
        #expect(style.vehicleOutlineWidth > 0)
        #expect(style.stopDiameter > 0)
        #expect(style.stopOutlineWidth > 0)
        #expect(style.routeLineWidth > 0)
        #expect((0 ... 1).contains(style.routeLuminance))
        #expect((0 ... 1).contains(style.inferredOpacityMultiplier))
    }

    @Test func projectionLabelsStayVisuallySubordinateToMarks() {
        let projection = ThrowStylesheet.ProjectionStyle.standard

        #expect(
            projection.label.headline.font == .system(
                size: 10,
                weight: .regular,
                design: .monospaced,
            ),
        )
        #expect(
            projection.label.detail.font == .system(
                size: 7,
                weight: .regular,
                design: .monospaced,
            ),
        )
        #expect((0 ..< 1).contains(projection.label.headline.luminanceMultiplier))
        #expect(
            projection.label.detail.luminanceMultiplier <
                projection.label.headline.luminanceMultiplier,
        )
        #expect(projection.label.routeTracking < 0)
        #expect(projection.label.offset > 0)
    }

    @Test func everyCuratedCarrierHasABoundedMutedBrandDotColor() {
        let style = ThrowStylesheet.AircraftStyle.standard

        #expect(style.secondaryOpacityMultiplier == 0.35)
        #expect((0 ..< 1).contains(style.brandDotBrightnessMultiplier))
        #expect(style.brandColors.count == AirlineBrand.allCases.count)
        for color in style.brandColors.values {
            #expect((0 ... 1).contains(color.red))
            #expect((0 ... 1).contains(color.green))
            #expect((0 ... 1).contains(color.blue))
        }
    }

    @Test func brandDotProjectionPreservesPrimaryColorRatios() throws {
        let style = ThrowStylesheet.AircraftStyle.standard
        let primary = try #require(style.brandColors[.united])
        let projected = primary.projected(brightness: 0.65, intensity: 0.8)

        #expect(abs(max(projected.red, projected.green, projected.blue) - 0.52) < 0.000_001)
        #expect(
            abs(projected.green / projected.blue - primary.green / primary.blue) < 0.000_001,
        )
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

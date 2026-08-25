import RegionKit
import SwiftUI
import WhereCore

/// Annual location estimates presented as one passport-style visa endorsement.
/// Locations collapses the endorsement; calendars and feature discovery show
/// its complete region rows and optional stay-planning controls.
struct LocationForecastPanel: View {
    let forecasts: [LocationForecast]
    var plannedStay: PlannedStay?
    var editableRegions: [Region] = []
    var editAction: ((Region) -> Void)?
    var clearAction: (@MainActor () async throws -> Void)?
    var isCollapsible = false

    @State private var isExpanded = false

    @Environment(\.stylesheet) private var stylesheet

    private var style: WhereStylesheet.LocationForecastStyle {
        stylesheet.locationForecast
    }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: style.cornerRadius)
        let showsContent = !isCollapsible || isExpanded

        VStack(alignment: .leading, spacing: style.rowSpacing) {
            if isCollapsible {
                LocationForecastHeader(
                    elapsedDays: forecasts.first?.elapsedDays,
                    isExpanded: showsContent,
                    expansionAction: toggleExpansion,
                )
            } else {
                LocationForecastHeader(
                    elapsedDays: forecasts.first?.elapsedDays,
                    isExpanded: true,
                )
            }

            if showsContent {
                VStack(alignment: .leading, spacing: style.rowSpacing) {
                    ForEach(forecasts, id: \.region) { forecast in
                        if forecast.region != forecasts.first?.region {
                            LocationForecastPerforation()
                        }

                        LocationForecastRow(
                            forecast: forecast,
                            plannedStay: plannedStay,
                        )
                    }

                    if !editableRegions.isEmpty, let editAction {
                        LocationForecastPerforation()
                        LocationForecastControls(
                            editableRegions: editableRegions,
                            plannedStay: plannedStay,
                            editAction: editAction,
                            clearAction: clearAction,
                        )
                    }
                }
                .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .padding(style.padding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            ZStack {
                shape.fill(.background)
                LinearGradient(
                    colors: [
                        Color.primary.opacity(style.ink.surfaceWashOpacity),
                        .clear,
                        Color.primary.opacity(style.ink.surfaceWashOpacity * 0.45),
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing,
                )
                SecurityPrintRosette(
                    tint: .primary,
                    wobble: style.surface.rosetteWobble,
                    lineWidth: style.surface.rosetteLineWidth,
                    primaryRingSpacing: style.surface.primaryRingSpacing,
                    secondaryRingSpacing: style.surface.secondaryRingSpacing,
                    primaryOpacity: style.ink.rosettePrimaryOpacity,
                    secondaryOpacity: style.ink.rosetteSecondaryOpacity,
                )
            }
            .clipShape(shape)
            .allowsHitTesting(false)
        }
        .overlay {
            ZStack {
                shape.strokeBorder(
                    Color.primary.opacity(style.ink.surfaceOutlineOpacity),
                    lineWidth: style.surface.outlineWidth,
                )
                shape
                    .inset(by: style.surface.inset)
                    .strokeBorder(
                        Color.primary.opacity(style.ink.insetOutlineOpacity),
                        style: StrokeStyle(
                            lineWidth: style.surface.insetOutlineWidth,
                            dash: [
                                style.surface.insetDashLength,
                                style.surface.insetDashSpacing,
                            ],
                        ),
                    )
            }
            .allowsHitTesting(false)
        }
        .shadow(
            color: style.surface.shadowColor,
            radius: style.surface.shadowRadius,
            y: style.surface.shadowOffsetY,
        )
    }

    private func toggleExpansion() {
        withAnimation(style.expansionAnimation) {
            isExpanded.toggle()
        }
    }
}

#if DEBUG
    #Preview {
        let report = PreviewSupport.plannedStayYearReportModel()
        LocationForecastPanel(
            forecasts: report.forecasts.leadingForecasts(report: report.report),
            plannedStay: report.forecasts.activePlannedStay,
            editableRegions: [.california, .newYork],
            editAction: { _ in },
            clearAction: {},
        )
        .padding()
        .whereBroadwayRoot()
    }
#endif

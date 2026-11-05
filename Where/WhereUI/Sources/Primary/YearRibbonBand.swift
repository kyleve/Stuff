import RegionKit
import SwiftUI
import WhereCore

/// One calendar-proportional ribbon track, either combining every region into
/// per-day lanes or isolating one region for a non-color presentation.
struct YearRibbonBand: View {
    let days: [DayPresence]
    let year: Int
    let isolatedRegion: Region?

    @Environment(\.stylesheet) private var stylesheet
    @Environment(\.regionStyles) private var regionStyles

    var body: some View {
        let timeline = stylesheet.timeline
        let ribbon = timeline.ribbon

        ZStack(alignment: .leading) {
            Capsule()
                .fill(ribbon.track)

            Canvas { context, size in
                for day in days where day.day.year == year {
                    let regions = displayedRegions(for: day)
                    for (lane, region) in regions.enumerated() {
                        let rect = YearRibbonLayout.segmentRect(
                            day: day.day,
                            size: size,
                            lane: lane,
                            laneCount: regions.count,
                        )
                        context.fill(
                            Path(rect),
                            with: .color(regionStyles.style(for: region).tint),
                        )
                    }
                }
            }
        }
        .clipShape(.capsule)
        .overlay {
            Capsule()
                .stroke(
                    ribbon.border,
                    lineWidth: ribbon.borderWidth,
                )
        }
        .frame(maxWidth: .infinity)
        .frame(height: ribbon.height)
    }

    private func displayedRegions(for day: DayPresence) -> [Region] {
        if let isolatedRegion {
            day.regions.contains(isolatedRegion) ? [isolatedRegion] : []
        } else {
            Region.inCanonicalOrder(day.regions)
        }
    }
}

#if DEBUG
    #Preview {
        let report = PreviewSupport.sampleReport()
        YearRibbonBand(
            days: report.days,
            year: report.year,
            isolatedRegion: nil,
        )
        .padding()
        .whereBroadwayRoot()
    }
#endif

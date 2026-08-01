import Charts
import SnapshotKit
import SwiftUI

/// A whole-year donut whose mutually exclusive slices always total exactly the
/// selected year's 365 or 366 calendar days.
struct YearBreakdownView: View {
    let overview: YearOverview

    @Environment(\.stylesheet) private var stylesheet
    @Environment(\.regionStyles) private var regionStyles

    private var style: WhereStylesheet.YearOverviewStyle {
        stylesheet.yearOverview
    }

    var body: some View {
        ScrollView {
            LazyVStack(spacing: style.breakdown.chartLegendSpacing) {
                ZStack {
                    Chart(overview.slices) { slice in
                        SectorMark(
                            angle: .value("Days", slice.days),
                            innerRadius: .ratio(style.breakdown.innerRadiusRatio),
                            angularInset: style.breakdown.angularInset,
                        )
                        .foregroundStyle(color(for: slice.id))
                        .accessibilityLabel(WhereFormat.yearOverviewSliceName(slice.id))
                        .accessibilityValue(WhereFormat.dayCount(slice.days))
                    }
                    .chartLegend(.hidden)
                    .accessibilityLabel(String(localized: .yearBreakdownAccessibilityLabel))

                    VStack(spacing: stylesheet.spacing.small) {
                        Text(WhereFormat.yearText(overview.year))
                            .font(.headline)
                        Text(WhereFormat.yearOverviewRecorded(
                            recorded: overview.recordedDayCount,
                            total: overview.dayCount,
                        ))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                    }
                    .padding()
                    .frame(maxWidth: style.breakdown.maxChartSize
                        * style.breakdown.innerRadiusRatio
                        * style.breakdown.centerContentWidthRatio)
                    .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
                    .accessibilityElement(children: .combine)
                }
                .frame(maxWidth: style.breakdown.maxChartSize)
                .aspectRatio(1, contentMode: .fit)
                .frame(maxWidth: .infinity)

                LazyVStack(spacing: style.breakdown.legendRowSpacing) {
                    ForEach(overview.slices) { slice in
                        YearBreakdownLegendRow(
                            title: WhereFormat.yearOverviewSliceName(slice.id),
                            dayCount: WhereFormat.dayCount(slice.days),
                            symbol: symbol(for: slice.id),
                            color: color(for: slice.id),
                        )
                    }
                }
            }
            .padding()
        }
    }

    private func color(for id: YearOverview.Slice.ID) -> Color {
        switch id {
            case let .region(region): regionStyles.style(for: region).tint
            case .multipleLocations: style.multipleLocationsColor
            case .unrecorded: style.unrecordedColor
            case .remaining: style.remainingColor
        }
    }

    private func symbol(for id: YearOverview.Slice.ID) -> String {
        switch id {
            case let .region(region): regionStyles.style(for: region).symbolName
            case .multipleLocations: "arrow.triangle.branch"
            case .unrecorded: "exclamationmark.circle.fill"
            case .remaining: "clock.fill"
        }
    }
}

#if DEBUG
    extension YearBreakdownView: SnapshotProviding {
        static var snapshots: [SnapshotCase] {
            whereSnapshot(name: "Loaded", configurations: .screenDefaults) {
                NavigationStack {
                    YearBreakdownView(overview: PreviewSupport.loadedYearOverview())
                        .navigationTitle(String(localized: .yearBreakdownTitle))
                }
            }
            whereSnapshot(name: "MissingDays", configurations: .phoneLightDark) {
                NavigationStack {
                    YearBreakdownView(overview: PreviewSupport.missingDaysYearOverview())
                        .navigationTitle(String(localized: .yearBreakdownTitle))
                }
            }
            whereSnapshot(name: "MultiRegion", configurations: .phoneLightDark) {
                NavigationStack {
                    YearBreakdownView(overview: PreviewSupport.multiRegionYearOverview())
                        .navigationTitle(String(localized: .yearBreakdownTitle))
                }
            }
        }
    }

    #Preview {
        YearBreakdownView.snapshotPreviews
    }
#endif

#if DEBUG
    extension YearBreakdownView: WhereFlyoverProviding {
        static let flyoverData = WhereFlyoverData.snapshots(
            YearBreakdownView.self,
            title: "Breakdown",
        )
    }
#endif

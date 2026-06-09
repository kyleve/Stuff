import SwiftUI
import WhereCore

/// The booklet's opening "bio-data" page: the gilt crest and wordmark over
/// passport-style identity fields summarizing the selected year, finished
/// with a decorative machine-readable zone along the bottom edge.
struct PassportBioPage: View {
    @Environment(WhereModel.self) private var model
    var tilt: TiltProvider?

    /// MRZ lines are padded to this many characters, mirroring the fixed-width
    /// code lines of a real passport's bio page.
    private static let mrzLength = 44

    /// Distinct regions with at least one day this year. The ranking already
    /// drops zero-day regions, so this is just its total entry count.
    private var regionCount: Int {
        model.ranking.primary.count + model.ranking.secondary.count
    }

    /// Year without a grouping separator ("2026", never "2,026").
    private var yearText: String {
        model.selectedYear.formatted(.number.grouping(.never))
    }

    /// Fraction of the year's calendar days with any tracked presence.
    private var coverage: Double {
        guard model.daysInSelectedYear > 0 else { return 0 }
        return Double(model.trackedDayCount) / Double(model.daysInSelectedYear)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: UIConstants.Spacings.xxLarge) {
            PassportCrest(tilt: tilt)
                .frame(maxWidth: .infinity)
                .padding(.bottom, UIConstants.Spacings.medium)

            PassportMasthead(title: Strings.primaryTitle, tilt: tilt)

            Text(Strings.passportSubtitle(year: model.selectedYear))
                .font(.system(.footnote, design: .serif).weight(.semibold))
                .textCase(.uppercase)
                .tracking(2)
                .foregroundStyle(GoldFoil.solid)

            fields
                .padding(.top, UIConstants.Spacings.large)

            Spacer(minLength: UIConstants.Spacings.xxLarge)

            machineReadableZone
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    /// The passport-style identity grid: tiny uppercase labels over serif
    /// values, two fields per row.
    private var fields: some View {
        Grid(
            alignment: .topLeading,
            horizontalSpacing: UIConstants.Spacings.xxLarge,
            verticalSpacing: UIConstants.Spacings.xxLarge,
        ) {
            GridRow {
                BioField(label: Strings.passportFieldYear, value: yearText)
                BioField(
                    label: Strings.passportFieldDaysLogged,
                    value: model.trackedDayCount.formatted(),
                )
            }
            GridRow {
                BioField(label: Strings.passportFieldRegions, value: regionCount.formatted())
                BioField(
                    label: Strings.passportFieldCoverage,
                    value: coverage.formatted(.percent.precision(.fractionLength(0))),
                )
            }
        }
    }

    /// A page-wide faux MRZ derived from the year's totals. Purely
    /// decorative — hidden from assistive tech, like the card MRZ.
    private var machineReadableZone: some View {
        VStack(alignment: .leading, spacing: UIConstants.Spacings.xSmall) {
            Rectangle()
                .fill(GoldFoil.solid.opacity(0.25))
                .frame(height: 1)
            ForEach(Array(mrzLines.enumerated()), id: \.offset) { _, line in
                Text(verbatim: line)
                    .font(.system(
                        size: UIConstants.Size.mrzFontSize,
                        weight: .medium,
                        design: .monospaced,
                    ))
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
            }
        }
        .foregroundStyle(GoldFoil.solid.opacity(0.6))
        .accessibilityHidden(true)
    }

    private var mrzLines: [String] {
        let days = String(format: "%03d", model.trackedDayCount)
        let span = String(format: "%03d", model.daysInSelectedYear)
        let line1 = "P<WHR<DOCUMENT<OF<PRESENCE"
            .padding(toLength: Self.mrzLength, withPad: "<", startingAt: 0)
        let line2 = "WHR\(yearText)<\(days)OF\(span)<<REG\(regionCount)"
            .padding(toLength: Self.mrzLength, withPad: "<", startingAt: 0)
        return [line1, line2]
    }
}

/// One bio-data entry: a tiny uppercase label over a serif value, the way a
/// passport prints "SURNAME" over the holder's name.
private struct BioField: View {
    let label: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: UIConstants.Spacings.xxSmall) {
            Text(label)
                .font(.caption2.weight(.semibold))
                .textCase(.uppercase)
                .tracking(1)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(.title3, design: .serif).weight(.semibold))
                .foregroundStyle(.primary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

#if DEBUG
    #Preview {
        ZStack {
            Color(red: 0.05, green: 0.05, blue: 0.09).ignoresSafeArea()
            PassportBioPage()
                .padding()
                .environment(\.colorScheme, .dark)
        }
        .environment(PreviewSupport.loadedModel())
    }
#endif

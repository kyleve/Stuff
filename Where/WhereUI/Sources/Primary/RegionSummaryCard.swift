import SwiftUI
import WhereCore

/// A Liquid Glass card summarizing how many days were spent in one region.
/// Used prominently on the Primary tab and (more compactly) on Elsewhere.
struct RegionSummaryCard: View {
    let regionDays: RegionDays
    var caption: String?
    var compact = false

    /// Calendar days in the year being summarized; the ambient bar is drawn as
    /// a fraction of this. Callers pass the selected year's real length
    /// (`WhereModel.daysInSelectedYear`); the default is only for previews.
    var yearLength = 365

    private var style: RegionStyle {
        regionDays.region.style
    }

    private var fraction: Double {
        guard yearLength > 0 else { return 0 }
        return min(1, Double(regionDays.days) / Double(yearLength))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: compact ? 10 : 16) {
            HStack(spacing: 12) {
                Text(style.emoji)
                    .font(compact ? .title2 : .largeTitle)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 2) {
                    Text(regionDays.region.localizedName)
                        .font(compact ? .headline : .title3.weight(.semibold))
                    if let caption {
                        Text(caption)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer(minLength: 0)

                Image(systemName: style.symbolName)
                    .font(compact ? .body : .title3)
                    .foregroundStyle(style.tint)
                    .accessibilityHidden(true)
            }

            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(regionDays.days, format: .number)
                    .font(
                        compact
                            ? .system(.title, design: .rounded, weight: .bold)
                            : .system(size: 46, weight: .bold, design: .rounded),
                    )
                    .contentTransition(.numericText())
                    .foregroundStyle(style.tint)
                Text(regionDays.days == 1 ? "day" : "days")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.secondary)
            }

            Capsule()
                .fill(.quaternary)
                .frame(height: 6)
                .overlay(alignment: .leading) {
                    GeometryReader { proxy in
                        Capsule()
                            .fill(style.tint.gradient)
                            .frame(width: proxy.size.width * fraction)
                    }
                }
                .frame(height: 6)
                .accessibilityHidden(true)
        }
        .padding(compact ? 16 : 22)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassEffect(
            .regular.tint(style.tint.opacity(0.18)),
            in: RoundedRectangle(cornerRadius: compact ? 22 : 28, style: .continuous),
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            "\(regionDays.region.localizedName): \(regionDays.days) days",
        )
    }
}

#if DEBUG
    #Preview {
        VStack {
            RegionSummaryCard(
                regionDays: RegionDays(region: .california, days: 148),
                caption: "Home base",
            )
            RegionSummaryCard(
                regionDays: RegionDays(region: .newYork, days: 22),
                compact: true,
            )
        }
        .padding()
    }
#endif

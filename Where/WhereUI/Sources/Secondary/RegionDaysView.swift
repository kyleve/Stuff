import SwiftUI
import WhereCore

/// Drill-in from an Elsewhere card: the individual days that counted for a
/// region this year. This is the "see where those check-ins are" view — each
/// row is a day, tappable to correct a wrong attribution via `DayRelabelView`.
struct RegionDaysView: View {
    @Environment(WhereModel.self) private var model

    let region: Region

    private var days: [DayPresence] {
        model.days(in: region)
    }

    var body: some View {
        content
            .navigationTitle(region.localizedName)
            .navigationBarTitleDisplayMode(.inline)
    }

    @ViewBuilder
    private var content: some View {
        if days.isEmpty {
            ContentUnavailableView {
                Label(Strings.secondaryRegionEmptyTitle, systemImage: "checkmark.circle")
            } description: {
                Text(Strings.secondaryRegionEmptyDescription)
            }
        } else {
            List {
                Section {
                    ForEach(days, id: \.date) { day in
                        NavigationLink {
                            DayRelabelView(day: day)
                        } label: {
                            DayRow(day: day)
                        }
                    }
                } footer: {
                    Text(Strings.secondaryRegionFooter)
                }
            }
            .accessibilityIdentifier("where_region_days_list")
        }
    }
}

/// One day in the region's list: the date and the regions it currently counts
/// for, so the user can spot the wrong ones at a glance.
private struct DayRow: View {
    let day: DayPresence

    var body: some View {
        HStack(spacing: UIConstants.Spacings.large) {
            Image(systemName: "calendar")
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: UIConstants.Spacings.xxSmall) {
                Text(dateText)
                    .font(.headline)
                Text(Strings.secondaryRegionCurrent(regions: regionsText))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, UIConstants.Spacings.xSmall)
        .accessibilityElement(children: .combine)
    }

    private var dateText: String {
        day.date.formatted(.dateTime.weekday(.wide).month(.wide).day().year())
    }

    /// Region names joined in declaration order so the caption is stable.
    private var regionsText: String {
        Region.allCases
            .filter { day.regions.contains($0) }
            .map(\.localizedName)
            .joined(separator: ", ")
    }
}

#if DEBUG
    #Preview {
        NavigationStack {
            RegionDaysView(region: .other)
                .environment(PreviewSupport.elsewhereOnlyModel())
        }
    }
#endif

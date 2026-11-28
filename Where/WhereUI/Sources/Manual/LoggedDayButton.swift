import RegionKit
import SFSafeSymbols
import SwiftUI
import WhereCore

/// One logged day: an icon marking backfill vs. override, the date, the regions
/// it counts for, a "Logged"/"Overridden" tag, and the audit note if one was
/// saved with the entry.
struct LoggedDayButton: View {
    let day: DayPresence
    let edit: () -> Void
    @Environment(\.stylesheet) private var stylesheet

    var body: some View {
        Button(action: edit) {
            HStack(alignment: .top, spacing: stylesheet.spacing.large) {
                Image(systemSymbol: day.isAuthoritative ? .pencilCircle : .calendarBadgePlus)
                    .font(.title3)
                    .foregroundStyle(.tint)
                    .fixedSize()
                    .frame(minWidth: stylesheet.size.statusIconWidth)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: stylesheet.spacing.xxSmall) {
                    Text(dateText)
                        .font(.headline)
                    Text(regionsText)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    if let note = day.audit?.note, !note.isEmpty {
                        Text(note)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .lineLimit(stylesheet.loggedDay.layout == .stacked ? nil : 2)
                    }
                    if stylesheet.loggedDay.layout == .stacked {
                        kindLabel
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                if stylesheet.loggedDay.layout == .inline {
                    Spacer(minLength: stylesheet.spacing.small)
                    kindLabel.fixedSize()
                }
            }
            .padding(.vertical, stylesheet.spacing.xxSmall)
            // Make the whole row (including the spacer) tap into the edit sheet.
            .contentShape(.rect)
            .accessibilityElement(children: .combine)
        }
        .buttonStyle(.plain)
    }

    private var kindLabel: some View {
        Text(kindText)
            .font(.caption)
            .foregroundStyle(.secondary)
    }

    private var dateText: String {
        day.displayDate.formatted(.dateTime.weekday(.abbreviated).month(.wide).day().year())
    }

    private var kindText: String {
        day
            .isAuthoritative ? String(localized: .loggedDaysKindOverridden) :
            String(localized: .loggedDaysKindLogged)
    }

    /// Region names joined in canonical order so the caption is stable.
    private var regionsText: String {
        Region.inCanonicalOrder(day.regions)
            .map(\.localizedName)
            .joined(separator: ", ")
    }
}

#if DEBUG
    #Preview("Logged day") {
        if let day = PreviewSupport.sampleManualDays().first {
            LoggedDayButton(day: day, edit: {}).padding().whereBroadwayRoot()
        }
    }
#endif

import SnapshotKit
import SwiftUI

/// Deterministic stand-in for a compact `DatePicker` under snapshot capture.
///
/// The live compact picker's value capsule renders relative to the real-world
/// date: it reserves its width from *today's* date in the medium format and
/// falls back to a short numeric format ("7/15/26") whenever the selection's
/// medium string doesn't fit that reservation — so the same pinned selection
/// renders differently depending on the day the test runs, and no settle
/// window can stabilize it. Captures substitute this row instead: the same
/// title + trailing-capsule layout, with the selection rendered in a fixed
/// format and locale so the image is a pure function of the selected value.
/// Only the system-drawn value capsule is substituted — the row title and
/// surrounding Form chrome stay real — per the `\.isCapturingSnapshot`
/// carve-out (see SnapshotKit's `SnapshotCaptureFlag`).
struct SnapshotDatePickerStandIn: View {
    /// The capsule's content — a calendar date or a time of day — each with a
    /// fixed format and locale so rendering can't depend on the wall clock.
    enum Selection {
        case date(Date)
        case timeOfDay(Date)
    }

    let title: String
    let selection: Selection

    var body: some View {
        LabeledContent(title) {
            Text(formattedSelection)
                .foregroundStyle(.primary)
                // Mimics the compact picker's system capsule chrome — fixed
                // system-control geometry, not themed stylesheet tokens.
                .padding(.horizontal, 11)
                .padding(.vertical, 6)
                .background(Color(.tertiarySystemFill), in: .capsule)
        }
    }

    private var formattedSelection: String {
        switch selection {
            case let .date(date):
                date.formatted(Self.dateStyle)
            case let .timeOfDay(date):
                date.formatted(Self.timeStyle)
        }
    }

    /// The medium date the live picker prefers ("Jul 15, 2026"), now with a
    /// fixed locale and no dependence on today's capsule-width reservation.
    private static let dateStyle = Date.FormatStyle(
        date: .abbreviated,
        time: .omitted,
        locale: Locale(identifier: "en_US"),
    )

    /// Shortened time ("8:00 PM") in the same fixed locale.
    private static let timeStyle = Date.FormatStyle(
        date: .omitted,
        time: .shortened,
        locale: Locale(identifier: "en_US"),
    )
}

#if DEBUG
    #Preview {
        Form {
            SnapshotDatePickerStandIn(
                title: "Day",
                selection: .date(PreviewSupport.referenceNow),
            )
            SnapshotDatePickerStandIn(
                title: "Remind me at",
                selection: .timeOfDay(PreviewSupport.referenceNow),
            )
        }
    }
#endif

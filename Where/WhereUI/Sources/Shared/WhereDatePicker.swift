import SnapshotKit
import SwiftUI

/// A compact `DatePicker` for Where's forms that renders a deterministic
/// stand-in under snapshot capture instead of the live system picker.
///
/// The live compact picker's value capsule renders relative to the real-world
/// date, so no reference image containing it is stable across days (see
/// ``SnapshotDatePickerStandIn``). Views use `WhereDatePicker` rather than
/// reading `\.isCapturingSnapshot` and branching themselves — the capture
/// handling, and the stand-in, stay a private detail here, so product code
/// carries no snapshot-environment checks.
struct WhereDatePicker: View {
    let title: String
    @Binding var selection: Date
    /// Optional inclusive selectable bounds, mapped onto `DatePicker`'s `in:`
    /// range overloads. `nil` means unbounded on that end.
    var earliest: Date?
    var latest: Date?
    let displayedComponents: DatePickerComponents

    @Environment(\.isCapturingSnapshot) private var isCapturingSnapshot

    init(
        _ title: String,
        selection: Binding<Date>,
        earliest: Date? = nil,
        latest: Date? = nil,
        displayedComponents: DatePickerComponents,
    ) {
        self.title = title
        _selection = selection
        self.earliest = earliest
        self.latest = latest
        self.displayedComponents = displayedComponents
    }

    var body: some View {
        if isCapturingSnapshot {
            SnapshotDatePickerStandIn(title: title, selection: standInSelection)
        } else {
            livePicker
        }
    }

    @ViewBuilder
    private var livePicker: some View {
        if let earliest, let latest {
            DatePicker(
                title,
                selection: $selection,
                in: earliest ... latest,
                displayedComponents: displayedComponents,
            )
        } else if let latest {
            DatePicker(
                title,
                selection: $selection,
                in: ...latest,
                displayedComponents: displayedComponents,
            )
        } else if let earliest {
            DatePicker(
                title,
                selection: $selection,
                in: earliest...,
                displayedComponents: displayedComponents,
            )
        } else {
            DatePicker(title, selection: $selection, displayedComponents: displayedComponents)
        }
    }

    /// A capsule showing the date for a `.date` picker, or the time of day for a
    /// `.hourAndMinute` one.
    private var standInSelection: SnapshotDatePickerStandIn.Selection {
        displayedComponents.contains(.date) ? .date(selection) : .timeOfDay(selection)
    }
}

/// Deterministic stand-in for a compact `DatePicker` under snapshot capture —
/// a private detail of ``WhereDatePicker``.
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
private struct SnapshotDatePickerStandIn: View {
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
            WhereDatePicker(
                "Day",
                selection: .constant(PreviewSupport.referenceNow),
                displayedComponents: .date,
            )
            WhereDatePicker(
                "Remind me at",
                selection: .constant(PreviewSupport.referenceNow),
                displayedComponents: .hourAndMinute,
            )
        }
    }
#endif

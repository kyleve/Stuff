import RegionKit
import SnapshotKit
import SwiftUI
import WhereCore

/// Shared read-only sections for initial inspection and a chosen proposal. The enclosing
/// review owns scope editing and save actions; these sections never create a source choice.
struct RecordingChoiceDetails: View {
    enum Mode { case inspection, proposal }

    let comparison: RecordingChoicePresentation.Comparison
    let mode: Mode

    var body: some View {
        Section {
            ForEach(comparison.explanations) { explanation in
                VStack(alignment: .leading) {
                    Text(explanation.text)
                    Text(WhereFormat.recordingPeriod(explanation.period))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .accessibilityElement(children: .combine)
            }
        } header: {
            Text(String(localized: .recordingReviewCurrentSelection))
        } footer: {
            Text(String(localized: .recordingReviewRawDetail))
        }
        ForEach(comparison.tracks) { track in
            RecordingTrackSection(track: track)
        }
        Section {
            RecordingContributionsRows(
                title: String(localized: .recordingReviewBefore),
                days: comparison.before,
            )
            if mode == .proposal {
                RecordingContributionsRows(
                    title: String(localized: .recordingReviewAfter),
                    days: comparison.after,
                )
                if !comparison.remainingIssues.isEmpty {
                    Text(String(localized: .recordingReviewRemaining(comparison.remainingIssues
                            .count)))
                    ForEach(comparison.remainingIssues) { issue in
                        RecordingRemainingIssueRow(issue: issue)
                    }
                }
            }
        } header: {
            Text(String(localized: .recordingReviewContributions))
        } footer: {
            Text(String(localized: .recordingReviewContributionsDetail))
        }
    }
}

private struct RecordingTrackSection: View {
    let track: RecordingChoicePresentation.Track

    var body: some View {
        Section {
            LabeledContent(String(localized: .recordingReviewRecordedDates)) {
                Text(WhereFormat.recordingDays(track.days))
            }
            if !track.map.pins.isEmpty || !track.map.routes.isEmpty {
                RecordedPointsMap(data: track.map)
                    .listRowInsets(EdgeInsets())
                    .accessibilityLabel(track.name)
            }
            if track.gaps.isEmpty {
                Text(String(localized: .recordingReviewNoGaps))
                    .foregroundStyle(.secondary)
            } else {
                DisclosureGroup(String(localized: .recordingReviewGaps(track.gaps.count))) {
                    RecordingGapRows(gaps: track.gaps)
                }
            }
            DisclosureGroup(String(localized: .recordingReviewRawPoints(track.observations
                    .count)))
            {
                RecordingObservationRows(observations: track.observations)
            }
        } header: {
            Text(track.name)
        }
    }
}

private struct RecordingRemainingIssueRow: View {
    let issue: RecordingChoicePresentation.RemainingIssue

    var body: some View {
        VStack(alignment: .leading) {
            Text(WhereFormat.recordingDays(issue.days))
            Text(issue.explanation).foregroundStyle(.secondary)
            Text(WhereFormat.recordingPeriod(issue.period))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
    }
}

private struct RecordingGapRows: View {
    let gaps: [RecordingPeriod]

    var body: some View {
        ForEach(gaps, id: \.self) { gap in
            Text(WhereFormat.recordingPeriod(gap))
        }
        Text(String(localized: .recordingReviewGapsDetail)).foregroundStyle(.secondary)
    }
}

private struct RecordingObservationRows: View {
    let observations: [RecordingObservation]

    var body: some View {
        ForEach(observations, id: \.sample.id) { observation in
            RecordingObservationRow(observation: observation)
        }
    }
}

private struct RecordingObservationRow: View {
    let observation: RecordingObservation

    var body: some View {
        VStack(alignment: .leading) {
            Text(String(localized: .recordingReviewObservationTime(WhereFormat
                    .recordingInstant(observation.sample.timestamp))))
            Text(WhereFormat.recordingObservation(observation))
                .foregroundStyle(.secondary)
            Text(WhereFormat.recordedFlightCoordinate(observation.sample.coordinate))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
    }
}

private struct RecordingContributionsRows: View {
    let title: String
    let days: [DayPresence]

    var body: some View {
        Text(title).font(.headline).accessibilityAddTraits(.isHeader)
        if days.isEmpty {
            Text(String(localized: .recordingReviewNoContributions))
                .foregroundStyle(.secondary)
        } else {
            ForEach(days, id: \.day) { day in
                LabeledContent(WhereFormat.calendarDay(
                    day.day,
                    format: .dateTime.month(.abbreviated).day().year(),
                )) {
                    Text(WhereFormat.recordingRegions(day))
                }
            }
        }
    }
}

#if DEBUG
    extension RecordingChoiceDetails: SnapshotProviding {
        static var snapshots: [SnapshotCase] {
            // Native Form composition is shared across themes. Compare the child maps and
            // dense date/region rows in one sheet; compact cases cover the other content states.
            whereThemeSnapshot(
                name: "Selected",
                configurations: .fullContentPhoneLightDarkWithAX5AndAnnotations,
                measurementReadiness: .immediate,
            ) {
                NavigationStack {
                    Form {
                        RecordingChoiceDetails(
                            comparison: RecordingChoicePreview.comparison(.selected),
                            mode: .proposal,
                        )
                    }
                    .navigationTitle(String(localized: .recordingReviewTitle))
                }
            }
            whereSnapshot(
                name: "Conflict",
                configurations: .fullContentPhoneLightDark,
                measurementReadiness: .immediate,
            ) {
                NavigationStack {
                    Form {
                        RecordingChoiceDetails(
                            comparison: RecordingChoicePreview.comparison(.conflict),
                            mode: .inspection,
                        )
                    }
                    .navigationTitle(String(localized: .recordingReviewTitle))
                }
            }
            whereSnapshot(
                name: "UnknownDates",
                configurations: [.init(device: .iPhoneFullContent)],
                measurementReadiness: .immediate,
            ) {
                NavigationStack {
                    Form {
                        RecordingChoiceDetails(
                            comparison: RecordingChoicePreview.comparison(.unknownDates),
                            mode: .proposal,
                        )
                    }
                    .navigationTitle(String(localized: .recordingReviewTitle))
                }
            }
            whereSnapshot(
                name: "UnknownGeography",
                configurations: [.init(device: .iPhoneFullContent)],
                measurementReadiness: .immediate,
            ) {
                NavigationStack {
                    Form {
                        RecordingChoiceDetails(
                            comparison: RecordingChoicePreview.comparison(.unknownGeography),
                            mode: .proposal,
                        )
                    }
                    .navigationTitle(String(localized: .recordingReviewTitle))
                }
            }
            // Exercise the same expanded disclosure content without snapshot-only state in
            // the production groups. These are rendering fixtures, not interaction coverage.
            whereSnapshot(
                name: "ExpandedEvidence",
                configurations: .fullContentPhoneLightDarkWithAX5AndAnnotations,
                measurementReadiness: .immediate,
            ) {
                let track = RecordingChoicePreview.comparison(.selected).tracks[0]
                NavigationStack {
                    Form {
                        Section(String(localized: .recordingReviewGaps(track.gaps.count))) {
                            RecordingGapRows(gaps: track.gaps)
                        }
                        Section(String(localized: .recordingReviewRawPoints(track.observations
                                .count)))
                        {
                            RecordingObservationRows(observations: track.observations)
                        }
                    }
                    .navigationTitle(track.name)
                }
            }
        }
    }

    #Preview {
        RecordingChoiceDetails.snapshotPreviews
    }
#endif

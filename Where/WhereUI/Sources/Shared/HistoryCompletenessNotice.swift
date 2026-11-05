import SFSafeSymbols
import SnapshotKit
import SwiftUI
import WhereCore

/// Labels the exact displayed report's unresolved contributions, independently of issue alerts.
struct HistoryCompletenessNotice: View {
    let completeness: HistoryCompleteness
    let review: () -> Void
    @Environment(\.stylesheet.spacing) private var spacing

    var body: some View {
        if !completeness.isComplete {
            VStack(alignment: .leading, spacing: spacing.small) {
                Label(
                    String(localized: .historyIncompleteTitle),
                    systemSymbol: .exclamationmarkTriangle,
                )
                .font(.headline)
                if !completeness.affectedDays.isEmpty {
                    Text(String(localized: .historyIncompleteDays(
                        WhereFormat.dayCount(completeness.affectedDays.count),
                    )))
                    .font(.subheadline)
                }
                if completeness.hasUnassignedDays {
                    Text(.historyIncompleteUnknownDates).font(.subheadline)
                }
                Button(String(localized: .historyIncompleteReview), action: review)
                    .accessibilityIdentifier("where_history_completeness_review")
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("where_history_incomplete")
        }
    }
}

#if DEBUG
    extension HistoryCompletenessNotice: SnapshotProviding {
        static var snapshots: [SnapshotCase] {
            for scenario in RecordingReportPreviewFixture.Scenario.allCases {
                let fixture = RecordingReportPreviewFixture(scenario: scenario)
                whereSnapshot(
                    name: scenario.rawValue,
                    configurations: scenario == .mixed ?
                        .fullContentPhoneLightDarkWithAX5AndAnnotations :
                        [.init(device: .iPhoneFullContent)],
                    onReadyToMeasure: { await fixture.prepare() },
                ) {
                    RecordingReportPreview(fixture: fixture) { report, _ in
                        ScrollView { Color.clear.frame(height: 1) }
                            .background(Color(uiColor: .systemBackground))
                            .historyCompletenessNotice(report.report?.completeness, report: report)
                    }
                }
            }
        }
    }

    #Preview { HistoryCompletenessNotice.snapshotPreviews }
#endif

extension View {
    /// Keep the qualifier visible with counts, including empty reports and initially scrolled
    /// timelines.
    func historyCompletenessNotice(
        _ completeness: HistoryCompleteness?,
        report: YearReportModel,
    ) -> some View {
        modifier(HistoryCompletenessModifier(completeness: completeness, report: report))
    }
}

/// The all-history review outlives the notice when the displayed report becomes complete.
private struct HistoryCompletenessModifier: ViewModifier {
    let completeness: HistoryCompleteness?
    let report: YearReportModel
    @State private var showingReview = false

    func body(content: Content) -> some View {
        content.safeAreaInset(edge: .top, spacing: 0) {
            if let completeness, !completeness.isComplete {
                HistoryCompletenessNotice(
                    completeness: completeness,
                    review: { showingReview = true },
                )
                .padding()
                .background(.bar)
            }
        }
        .sheet(isPresented: $showingReview) {
            ResolutionView(report: report)
        }
    }
}

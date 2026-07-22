import SwiftUI
import WhereCore

/// Lists every piece of evidence captured in the selected year, newest first,
/// with a "+" to compose a new one in-app. Tapping a row pushes its detail
/// (metadata + attachment preview). Chrome-free (no `NavigationStack` / title):
/// the Your Data tab hosts it as the Attachments segment and owns the bar.
///
/// The list reloads whenever the year's evidence day-keys change (any committed
/// write, including a share-extension add synced back) and again each time the
/// compose sheet closes — so a second attachment on an already-marked day still
/// appears immediately.
struct EvidenceListView: View {
    let report: YearReportModel
    /// Whether this is the visible Your Data segment; gates the `+` toolbar item
    /// so the hidden (but still-mounted) segment doesn't also contribute it.
    var isActive: Bool

    @State private var model: EvidenceListModel
    @State private var showingAdd = false

    init(report: YearReportModel, isActive: Bool = true) {
        self.report = report
        self.isActive = isActive
        _model = State(initialValue: EvidenceListModel(services: report.services))
    }

    #if DEBUG
        /// Preview seam: inject a model already in a chosen state.
        init(report: YearReportModel, model: EvidenceListModel, isActive: Bool = true) {
            self.report = report
            self.isActive = isActive
            _model = State(initialValue: model)
        }
    #endif

    /// Inputs that should trigger a reload of the list.
    private struct LoadID: Equatable {
        let year: Int
        let evidenceDayKeys: Set<CalendarDay>
    }

    var body: some View {
        content
            .toolbar {
                if isActive {
                    ToolbarItem(placement: .topBarLeading) {
                        Button {
                            showingAdd = true
                        } label: {
                            Label(Strings.evidenceAdd, systemImage: "plus")
                        }
                        .accessibilityIdentifier("where_add_evidence_button")
                    }
                }
            }
            .navigationDestination(for: Evidence.self) { evidence in
                EvidenceDetailView(evidence: evidence, report: report)
            }
            .task(id: loadID) { await model.load(for: report.selectedYear) }
            .sheet(isPresented: $showingAdd, onDismiss: reloadAfterCompose) {
                AddEvidenceView(report: report)
            }
    }

    private var loadID: LoadID {
        LoadID(year: report.selectedYear, evidenceDayKeys: report.evidenceDayKeys)
    }

    /// A new attachment on a day that already had evidence leaves the day-keys
    /// (and thus `loadID`) unchanged, so reload explicitly when compose closes.
    private func reloadAfterCompose() {
        Task { await model.load(for: report.selectedYear) }
    }

    @ViewBuilder
    private var content: some View {
        switch model.loadState {
            case .idle, .loading:
                AppIconLoadingView(caption: Strings.primaryLoading)
            case let .loaded(items):
                list(items)
            case .empty:
                emptyState
            case let .failed(message):
                ContentUnavailableView {
                    Label(Strings.evidenceFailedTitle, systemImage: "exclamationmark.icloud")
                } description: {
                    Text(message)
                }
        }
    }

    private func list(_ items: [Evidence]) -> some View {
        List {
            // Newest first reads best for a growing archive; the store returns
            // ascending by `capturedAt`.
            ForEach(items.reversed()) { evidence in
                NavigationLink(value: evidence) {
                    EvidenceRow(evidence: evidence)
                }
            }
        }
        .listStyle(.plain)
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label(Strings.evidenceEmptyTitle, systemImage: "paperclip")
        } description: {
            Text(Strings.evidenceEmptyDescription)
        } actions: {
            Button(Strings.evidenceAdd) { showingAdd = true }
        }
    }
}

/// One evidence row: kind glyph, kind name, capture date, and a note snippet.
private struct EvidenceRow: View {
    let evidence: Evidence

    @Environment(\.stylesheet) private var stylesheet

    var body: some View {
        HStack(spacing: stylesheet.spacing.large) {
            Image(systemName: evidence.kind.symbolName)
                .font(.title3)
                .foregroundStyle(.tint)
                .frame(width: stylesheet.size.statusIconWidth)
            VStack(alignment: .leading, spacing: stylesheet.spacing.xxSmall) {
                Text(evidence.kind.displayName)
                    .font(.headline)
                Text(evidence.capturedAt.formatted(date: .abbreviated, time: .shortened))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                if let note = evidence.note, !note.isEmpty {
                    Text(note)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
        }
        .padding(.vertical, stylesheet.spacing.xxSmall)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            Strings.evidenceRowAccessibility(kind: evidence.kind, date: evidence.capturedAt),
        )
        // Log View Mode: reveal an inspect badge that opens this archive's
        // evidence-scope events. A no-op in release.
        .debugLogInspectable(WhereLog.evidence)
    }
}

#if DEBUG
    #Preview("Loaded") {
        NavigationStack {
            EvidenceListView(
                report: PreviewSupport.loadedYearReportModel(),
                model: PreviewSupport
                    .evidenceListModel(state: .loaded(PreviewSupport.sampleEvidence())),
            )
        }
    }

    #Preview("Empty") {
        NavigationStack {
            EvidenceListView(
                report: PreviewSupport.loadedYearReportModel(),
                model: PreviewSupport.evidenceListModel(state: .empty),
            )
        }
    }

    #Preview("Failed") {
        NavigationStack {
            EvidenceListView(
                report: PreviewSupport.loadedYearReportModel(),
                model: PreviewSupport.evidenceListModel(state: .failed("iCloud is unavailable.")),
            )
        }
    }
#endif

import SFSafeSymbols
import SwiftUI
import WhereCore

/// Lists every piece of evidence captured in the selected year, newest first,
/// with a "+" to compose a new one in-app. Tapping a row pushes its detail
/// (metadata + attachment preview). A drill-in from the Settings "Data" section
/// (the Attachments row), so it renders inside that `NavigationStack` and owns
/// only its title and toolbar.
///
/// The list reloads whenever the year's evidence day-keys change (any committed
/// write, including a share-extension add synced back) and again each time the
/// compose sheet closes — so a second attachment on an already-marked day still
/// appears immediately.
struct EvidenceListView: View {
    let report: YearReportModel

    @State private var model: EvidenceListModel
    @State private var showingAdd = false

    init(report: YearReportModel) {
        self.report = report
        _model = State(initialValue: EvidenceListModel(services: report.services))
    }

    #if DEBUG
        /// Preview seam: inject a model already in a chosen state.
        init(report: YearReportModel, model: EvidenceListModel) {
            self.report = report
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
            .navigationTitle(WhereFormat.evidenceListTitle(year: report.selectedYear))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showingAdd = true
                    } label: {
                        Label(String(localized: .evidenceAdd), systemSymbol: .plus)
                    }
                    .accessibilityIdentifier("where_add_evidence_button")
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
                AppIconLoadingView(caption: String(localized: .primaryLoading))
            case let .loaded(items):
                list(items)
            case .empty:
                emptyState
            case let .failed(message):
                ContentUnavailableView {
                    Label(
                        String(localized: .evidenceFailedTitle),
                        systemSymbol: .exclamationmarkIcloud,
                    )
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
            Label(String(localized: .evidenceEmptyTitle), systemSymbol: .paperclip)
        } description: {
            Text(String(localized: .evidenceEmptyDescription))
        } actions: {
            Button(String(localized: .evidenceAdd)) { showingAdd = true }
        }
    }
}

extension EvidenceListView: SettingsSection {
    static var destination: SettingsDestination {
        .attachments
    }

    enum Item: SettingsItem {
        case attachments

        var title: String {
            switch self {
                case .attachments: String(localized: .settingsAttachmentsRow)
            }
        }

        var keywords: [String] {
            switch self {
                case .attachments: splitKeywords(String(localized: .settingsKeywordsAttachments))
            }
        }
    }
}

/// One evidence row: kind glyph, kind name, capture date, and a note snippet.
private struct EvidenceRow: View {
    let evidence: Evidence

    @Environment(\.stylesheet) private var stylesheet

    var body: some View {
        HStack(spacing: stylesheet.spacing.large) {
            Image(systemSymbol: evidence.kind.symbol)
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
            WhereFormat.evidenceRowAccessibility(kind: evidence.kind, date: evidence.capturedAt),
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

#if DEBUG
    extension EvidenceListView: WhereFlyoverProviding {
        static let flyoverData = WhereFlyoverData(
            EvidenceListView.self,
            routes: [
                .push(to: EvidenceDetailView.flyoverID),
                .modal(to: AddEvidenceView.flyoverID),
            ],
        ) { id, world in
            .init(
                id: id,
                title: "Evidence",
                variants: [
                    WhereFlyoverData.hostedVariant(
                        id: "loaded",
                        title: "Loaded",
                        world: world,
                    ) {
                        EvidenceListView(
                            report: world.report,
                            model: PreviewSupport.evidenceListModel(
                                state: .loaded(PreviewSupport.sampleEvidence()),
                            ),
                        )
                    },
                    WhereFlyoverData.hostedVariant(
                        id: "empty",
                        title: "Empty",
                        world: world,
                    ) {
                        EvidenceListView(
                            report: world.report,
                            model: PreviewSupport.evidenceListModel(state: .empty),
                        )
                    },
                    WhereFlyoverData.hostedVariant(
                        id: "failed",
                        title: "Failed",
                        world: world,
                    ) {
                        EvidenceListView(
                            report: world.report,
                            model: PreviewSupport.evidenceListModel(
                                state: .failed("The attachment index is unavailable."),
                            ),
                        )
                    },
                ],
            )
        }
    }
#endif

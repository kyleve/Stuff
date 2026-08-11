import SFSafeSymbols
import SnapshotKit
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

    @Environment(\.stylesheet) private var stylesheet
    @State private var model: EvidenceListModel
    @State private var showingAdd = false
    private let automaticallyLoads: Bool

    init(report: YearReportModel) {
        self.report = report
        _model = State(initialValue: EvidenceListModel(services: report.services))
        automaticallyLoads = true
    }

    #if DEBUG
        /// Preview seam: inject a model already in a chosen state.
        init(report: YearReportModel, model: EvidenceListModel) {
            self.report = report
            _model = State(initialValue: model)
            automaticallyLoads = false
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
            .task(id: loadID) {
                guard automaticallyLoads else { return }
                await model.load(for: report.selectedYear)
            }
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
        let entries = items.reversed().enumerated().map {
            EvidenceArchiveEntry(index: $0.offset + 1, evidence: $0.element)
        }
        return List {
            EvidenceArchiveHeader(
                year: report.selectedYear,
                recordCount: entries.count,
            )
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
            .listRowInsets(EdgeInsets(
                top: stylesheet.spacing.large,
                leading: stylesheet.spacing.xxLarge,
                bottom: stylesheet.spacing.large,
                trailing: stylesheet.spacing.xxLarge,
            ))

            // Newest first reads best for a growing archive; the store returns
            // ascending by `capturedAt`.
            ForEach(entries) { entry in
                NavigationLink(value: entry.evidence) {
                    EvidenceRow(evidence: entry.evidence, recordIndex: entry.index)
                }
                .listRowBackground(stylesheet.palette.brand.raisedPaper)
                .listRowSeparatorTint(
                    stylesheet.palette.brand.brass
                        .opacity(stylesheet.evidence.archive.borderOpacity),
                )
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(stylesheet.palette.brand.canvas)
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

private struct EvidenceArchiveEntry: Identifiable {
    let index: Int
    let evidence: Evidence

    var id: UUID {
        evidence.id
    }
}

private struct EvidenceArchiveHeader: View {
    let year: Int
    let recordCount: Int

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.stylesheet) private var stylesheet

    var body: some View {
        let archive = stylesheet.evidence.archive
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: stylesheet.spacing.small) {
                    HStack(alignment: .top) {
                        documentLabel
                        Spacer(minLength: stylesheet.spacing.medium)
                        seal
                    }
                    title
                    recordCountLabel
                }
            } else {
                HStack(alignment: .top, spacing: stylesheet.spacing.large) {
                    VStack(alignment: .leading, spacing: stylesheet.spacing.small) {
                        documentLabel
                        title
                        recordCountLabel
                    }
                    Spacer(minLength: stylesheet.spacing.medium)
                    seal
                }
            }
        }
        .padding(archive.padding)
        .background(stylesheet.palette.brand.raisedPaper)
        .clipShape(RoundedRectangle(cornerRadius: archive.cornerRadius))
        .overlay {
            RoundedRectangle(cornerRadius: archive.cornerRadius)
                .stroke(
                    stylesheet.palette.brand.brass.opacity(archive.borderOpacity),
                    lineWidth: 0.75,
                )
        }
        .accessibilityElement(children: .combine)
    }

    private var documentLabel: some View {
        Text(String(localized: .evidenceArchiveDocumentLabel))
            .font(stylesheet.evidence.archive.eyebrowFont)
            .tracking(1.6)
            .foregroundStyle(stylesheet.palette.brand.brass)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var title: some View {
        Text(WhereFormat.evidenceArchiveTitle(year: year))
            .font(stylesheet.evidence.archive.titleFont)
            .foregroundStyle(stylesheet.palette.brand.ink)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var recordCountLabel: some View {
        Text(WhereFormat.evidenceArchiveRecordCount(recordCount))
            .font(.subheadline)
            .foregroundStyle(.secondary)
    }

    private var seal: some View {
        WhereSeal(tint: stylesheet.palette.brand.brass)
            .frame(width: stylesheet.evidence.archive.headerSealSize)
            .accessibilityHidden(true)
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
    let recordIndex: Int

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.stylesheet) private var stylesheet

    var body: some View {
        let archive = stylesheet.evidence.archive
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: stylesheet.spacing.small) {
                    HStack {
                        index
                        Rectangle()
                            .fill(stylesheet.palette.brand.brass.opacity(archive.borderOpacity))
                            .frame(height: 0.75)
                            .accessibilityHidden(true)
                        symbol
                    }
                    details
                }
            } else {
                HStack(alignment: .top, spacing: archive.rowSpacing) {
                    index
                        .frame(width: archive.indexWidth, alignment: .leading)
                    Rectangle()
                        .fill(stylesheet.palette.brand.brass.opacity(archive.borderOpacity))
                        .frame(width: 0.75)
                        .accessibilityHidden(true)
                    details
                }
            }
        }
        .padding(.vertical, stylesheet.spacing.small)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            WhereFormat.evidenceRowAccessibility(kind: evidence.kind, date: evidence.capturedAt),
        )
        // Log View Mode: reveal an inspect badge that opens this archive's
        // evidence-scope events. A no-op in release.
        .debugLogInspectable(WhereLog.evidence)
    }

    private var index: some View {
        Text(verbatim: String(format: "%02d", recordIndex))
            .font(stylesheet.evidence.archive.indexFont)
            .foregroundStyle(stylesheet.palette.brand.brass)
            .fixedSize(horizontal: true, vertical: false)
    }

    private var symbol: some View {
        Image(systemSymbol: evidence.kind.symbol)
            .font(.subheadline)
            .foregroundStyle(stylesheet.palette.brand.mineral)
            .accessibilityHidden(true)
    }

    private var details: some View {
        VStack(alignment: .leading, spacing: stylesheet.spacing.xSmall) {
            HStack(alignment: .firstTextBaseline) {
                Text(evidence.kind.displayName)
                    .font(stylesheet.evidence.archive.rowTitleFont)
                if !dynamicTypeSize.isAccessibilitySize {
                    Spacer(minLength: stylesheet.spacing.medium)
                    symbol
                }
            }
            Text(evidence.capturedAt.formatted(date: .abbreviated, time: .shortened))
                .font(.subheadline.monospacedDigit())
                .foregroundStyle(.secondary)
            if let note = evidence.note, !note.isEmpty {
                Text(note)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 2)
            }
        }
    }
}

#if DEBUG
    extension EvidenceListView: SnapshotProviding {
        static var snapshots: [SnapshotCase] {
            [
                whereSnapshot(
                    name: "Loaded",
                    configurations: .fullContentScreenDefaults + [
                        SnapshotConfiguration(
                            layoutDirection: .rightToLeft,
                            device: .iPhoneFullContent,
                        ),
                    ],
                    settle: .immediate,
                ) {
                    NavigationStack {
                        EvidenceListView(
                            report: PreviewSupport.loadedYearReportModel(),
                            model: PreviewSupport.evidenceListModel(
                                state: .loaded(PreviewSupport.sampleEvidence()),
                            ),
                        )
                    }
                },
                whereSnapshot(name: "Empty", configurations: .phoneLightDark) {
                    NavigationStack {
                        EvidenceListView(
                            report: PreviewSupport.loadedYearReportModel(),
                            model: PreviewSupport.evidenceListModel(state: .empty),
                        )
                    }
                },
                whereSnapshot(name: "Failed", configurations: .phoneLightDark) {
                    NavigationStack {
                        EvidenceListView(
                            report: PreviewSupport.loadedYearReportModel(),
                            model: PreviewSupport.evidenceListModel(
                                state: .failed("The attachment index is unavailable."),
                            ),
                        )
                    }
                },
            ]
        }
    }
#endif

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

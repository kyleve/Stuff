import SFSafeSymbols
import SnapshotKit
import SwiftUI
import WhereCore

/// A feature-marketing walkthrough for capturing travel evidence from another
/// app and finding it later in Where's attachment archive.
struct ShareEvidenceFeaturesView: View {
    let report: YearReportModel
    let focus: SettingsFocus?
    let presentation: FeatureDiscoveryPresentation

    @State private var evidence: EvidenceListModel
    @Environment(\.stylesheet) private var stylesheet
    private let loadsLiveEvidence: Bool

    init(
        report: YearReportModel,
        focus: SettingsFocus?,
        presentation: FeatureDiscoveryPresentation,
    ) {
        self.report = report
        self.focus = focus
        self.presentation = presentation
        _evidence = State(initialValue: EvidenceListModel(services: report.services))
        loadsLiveEvidence = true
    }

    #if DEBUG
        init(
            report: YearReportModel,
            focus: SettingsFocus?,
            presentation: FeatureDiscoveryPresentation,
            evidence: EvidenceListModel,
        ) {
            self.report = report
            self.focus = focus
            self.presentation = presentation
            _evidence = State(initialValue: evidence)
            loadsLiveEvidence = false
        }
    #endif

    var body: some View {
        StaggeredRevealScope {
            SettingsFocusScope(focus: focus) {
                Form {
                    FeatureMarketingHeader(
                        title: String(localized: .settingsExploreEvidenceTitle),
                        tagline: String(localized: .settingsExploreEvidenceTagline),
                        systemSymbol: SettingsDestination.shareEvidence.systemSymbol,
                        tint: SettingsDestination.shareEvidence.iconColor,
                    )
                    .listRowInsets(.init())
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                    .staggeredReveal(order: 0)

                    Section {
                        FeatureShareSheetPreview()
                            .featureMarketingRow(order: 1)
                            .settingsRow(Item.shareSheet, restingBackground: .clear)
                        FeatureEvidenceComposePreview(date: presentation.lockScreenDate)
                            .featureMarketingRow(order: 1)
                            .settingsRow(Item.compose, restingBackground: .clear)
                        FeatureEvidenceArchivePreview(content: archiveContent)
                            .featureMarketingRow(order: 2)
                            .settingsRow(Item.archive, restingBackground: .clear)
                        FeatureMarketingPanel {
                            NavigationLink(value: Route.archive) {
                                Label {
                                    Text(String(localized: .settingsExploreEvidenceOpenArchive))
                                        .foregroundStyle(.primary)
                                } icon: {
                                    Image(systemSymbol: .paperclip)
                                        .foregroundStyle(SettingsDestination.shareEvidence
                                            .iconColor)
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .featureMarketingRow(order: 2)
                    } footer: {
                        VStack(alignment: .leading, spacing: stylesheet.spacing.medium) {
                            Text(String(localized: .settingsExploreEvidenceFooter))
                            FeatureDiscoveryDataFooter()
                        }
                        .staggeredReveal(order: 2)
                    }
                }
                .scrollContentBackground(.hidden)
                .background(FeatureDiscoveryBackground())
                .navigationDestination(for: Route.self) { route in
                    switch route {
                        case .archive: EvidenceListView(report: report)
                    }
                }
            }
        }
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .task(id: report.selectedYear) {
            guard loadsLiveEvidence else { return }
            await evidence.load(for: report.selectedYear)
        }
    }

    private var archiveContent: FeatureEvidenceArchivePreview.Content {
        switch evidence.loadState {
            case .idle, .loading: .loading
            case let .loaded(items):
                if let latest = items.last { .actual(latest) }
                else { .example(presentation.lockScreenDate) }
            case .empty: .example(presentation.lockScreenDate)
            case .failed: .failed(presentation.lockScreenDate)
        }
    }

    private enum Route: Hashable {
        case archive
    }
}

extension ShareEvidenceFeaturesView: SettingsSection {
    static var destination: SettingsDestination {
        .shareEvidence
    }

    enum Item: SettingsItem {
        case shareSheet
        case compose
        case archive

        var title: String {
            switch self {
                case .shareSheet: String(localized: .settingsExploreEvidenceShareTitle)
                case .compose: String(localized: .settingsExploreEvidenceComposeTitle)
                case .archive: String(localized: .settingsExploreEvidenceArchiveTitle)
            }
        }

        var keywords: [String] {
            splitKeywords(String(localized: .settingsKeywordsEvidenceFeatures))
        }
    }
}

#if DEBUG
    extension ShareEvidenceFeaturesView: SnapshotProviding {
        static var snapshots: [SnapshotCase] {
            whereSnapshot(name: "Default", configurations: .fullContentScreenDefaults) {
                ShareEvidenceFeaturesView(
                    report: PreviewSupport.loadedYearReportModel(),
                    focus: nil,
                    presentation: PreviewSupport.featureDiscoveryPresentation(),
                    evidence: PreviewSupport.evidenceListModel(
                        state: .loaded(PreviewSupport.sampleEvidence()),
                    ),
                )
            }
        }
    }

    #Preview {
        NavigationStack { ShareEvidenceFeaturesView.snapshotPreviews }
            .whereBroadwayRoot()
    }
#endif

#if DEBUG
    extension ShareEvidenceFeaturesView: WhereFlyoverProviding {
        static let flyoverData = WhereFlyoverData.snapshots(
            ShareEvidenceFeaturesView.self,
            title: "Share & Evidence",
            routes: [.push(to: EvidenceListView.flyoverID)],
        )
    }
#endif

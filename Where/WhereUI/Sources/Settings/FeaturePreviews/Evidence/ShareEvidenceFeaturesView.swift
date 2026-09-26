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
                ShareEvidenceFeaturesContent(
                    report: report,
                    presentation: presentation,
                    archiveContent: archiveContent,
                )
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

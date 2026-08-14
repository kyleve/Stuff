import CreditKit
import RegionKit
import SnapshotKit
import SwiftUI
import WhereCore

/// Settings drill-in for what the app *is* rather than what it does: its privacy
/// promise, which build is running, the third-party work it is built with, and
/// where its bundled region boundaries came from.
///
/// Every fact here is vended by whoever owns it — `BuildInfo` and the generated
/// attribution report from `WhereCore`, `RegionDataSource` from `RegionKit` — so
/// this screen only renders and localizes. Adding a dependency means re-running
/// `./attribution`, and adding a dataset means regenerating RegionKit's; neither
/// is a change to this view.
///
/// Credits are split by `SoftwareCredit.Kind` into two sections rather than one
/// combined list, because a development tool is *not* in the binary the reader
/// is running; merging them would credit honestly but describe the app falsely.
struct AboutSettingsView: View {
    var focus: SettingsFocus?

    @Environment(\.stylesheet) private var stylesheet
    private let buildInfo: BuildInfo
    private let attribution: AttributionManifest?
    private let dataSources: [RegionDataSource]
    private let diagnosticReportingConfiguration: DiagnosticReportingConfiguration

    /// Defaults read the live values; the parameters exist so previews and tests
    /// can render a stamped build and a populated report, neither of which a
    /// bundle outside the app target carries.
    init(
        focus: SettingsFocus?,
        buildInfo: BuildInfo = .current(bundle: .main),
        attribution: AttributionManifest? = AppAttribution.main,
        dataSources: [RegionDataSource] = RegionDataSource.all,
        diagnosticReportingConfiguration: DiagnosticReportingConfiguration =
            .currentBuildDefaults,
    ) {
        self.focus = focus
        self.buildInfo = buildInfo
        self.attribution = attribution
        self.dataSources = dataSources
        self.diagnosticReportingConfiguration = diagnosticReportingConfiguration
    }

    var body: some View {
        SettingsFocusScope(focus: focus) {
            Form {
                PrivacyPassportCard(presentation: PrivacyPassportPresentation(
                    configuration: diagnosticReportingConfiguration,
                ), disclosureInteraction: .linkToSettings)
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                    .listRowInsets(EdgeInsets())
                versionSection
                dependenciesSection
                developmentToolsSection
                dataSourcesSection
                AboutOpenSourceFooter()
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                    .listRowInsets(EdgeInsets())
            }
        }
        .navigationTitle(String(localized: .settingsAboutHeader))
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: Version

    private var versionSection: some View {
        Section {
            LabeledContent(
                String(localized: .settingsAboutVersionRow),
                value: WhereFormat.aboutValue(buildInfo.version),
            )
            LabeledContent(
                String(localized: .settingsAboutBuildRow),
                value: WhereFormat.aboutValue(buildInfo.build),
            )
            LabeledContent(
                String(localized: .settingsAboutCommitRow),
                value: WhereFormat.aboutCommit(buildInfo.commit),
            )
        } header: {
            Text(String(localized: .settingsAboutVersionHeader))
        } footer: {
            Text(String(localized: .settingsAboutVersionFooter))
        }
        // Selectable so a bug report can carry the exact commit rather than a
        // squinted-at transcription of it.
        .textSelection(.enabled)
        .settingsRow(Item.version)
    }

    // MARK: Open source

    private var dependenciesSection: some View {
        creditSection(
            kind: .library,
            header: String(localized: .settingsAboutDependenciesHeader),
            footer: String(localized: .settingsAboutDependenciesFooter),
        )
        .settingsRow(Item.dependencies)
    }

    // MARK: Development tools

    private var developmentToolsSection: some View {
        creditSection(
            kind: .developmentTool,
            header: String(localized: .settingsAboutDevelopmentToolsHeader),
            footer: String(localized: .settingsAboutDevelopmentToolsFooter),
        )
        .settingsRow(Item.developmentTools)
    }

    private func creditSection(
        kind: SoftwareCredit.Kind,
        header: String,
        footer: String,
    ) -> some View {
        let credits = attribution?.credits(ofKind: kind) ?? []
        return Section {
            if credits.isEmpty {
                // Keyed on *this section* being empty, not on the report being
                // absent: a report that carries only libraries would otherwise
                // render the tools header and footer over no rows, and a footer
                // still promising a list to tap through reads as a broken screen
                // rather than as an empty one.
                Text(String(localized: emptyMessage))
                    .foregroundStyle(.secondary)
            } else {
                ForEach(credits) { credit in
                    // A closure-form link, not a `SettingsRoute`: routes are the
                    // top-level group vocabulary, and a leaf pushed from inside
                    // one group would need its own `navigationDestination`.
                    NavigationLink {
                        LicenseView(credit: credit)
                    } label: {
                        LabeledContent(credit.name) {
                            Text(credit.version)
                        }
                    }
                }
            }
        } header: {
            Text(header)
        } footer: {
            Text(footer)
        }
    }

    /// Why a section is empty, which the reader needs distinguished: no report
    /// at all means the whole build is unattributed, while an empty section of
    /// a real report means only that this kind has nothing in it.
    var emptyMessage: LocalizedStringResource {
        attribution == nil ? .settingsAboutAttributionUnavailable : .settingsAboutAttributionNone
    }

    // MARK: Data sources

    private var dataSourcesSection: some View {
        Section {
            ForEach(dataSources, id: \.name) { source in
                dataSourceRow(source)
            }
        } header: {
            Text(String(localized: .settingsAboutDataSourcesHeader))
        } footer: {
            Text(String(localized: .settingsAboutDataSourcesFooter))
        }
        .settingsRow(Item.dataSources)
    }

    private func dataSourceRow(_ source: RegionDataSource) -> some View {
        // Everything below the name is stacked rather than trailing-aligned: a
        // boundary set's name is long enough to wrap, and a trailing count that
        // sometimes drops to its own line reads as a different layout per row.
        VStack(alignment: .leading, spacing: stylesheet.spacing.xSmall) {
            Text(source.name)
            VStack(alignment: .leading, spacing: stylesheet.spacing.xxSmall) {
                // Only the prose is dimmed — a link tinted secondary alongside
                // it stops reading as tappable.
                Group {
                    Text(WhereFormat.regionDataSourceRegionCount(source.regions.count))
                    Text(WhereFormat.regionDataSourceFidelity(source.fidelity))
                    Text(WhereFormat.regionDataSourceLicense(source.license))
                }
                .foregroundStyle(.secondary)
                if let url = source.sourceURL {
                    Link(WhereFormat.regionDataSourcePublisher(url), destination: url)
                }
                if let url = source.obtainedFromURL {
                    Link(WhereFormat.regionDataSourceObtainedFrom(url), destination: url)
                }
            }
            .font(.caption)
        }
    }
}

extension AboutSettingsView: SettingsSection {
    static var destination: SettingsDestination {
        .about
    }

    enum Item: SettingsItem {
        case version
        case dependencies
        case developmentTools
        case dataSources

        var title: String {
            switch self {
                case .version: String(localized: .settingsAboutVersionHeader)
                case .dependencies: String(localized: .settingsAboutDependenciesHeader)
                case .developmentTools:
                    String(localized: .settingsAboutDevelopmentToolsHeader)
                case .dataSources: String(localized: .settingsAboutDataSourcesHeader)
            }
        }

        var keywords: [String] {
            switch self {
                case .version: splitKeywords(String(localized: .settingsKeywordsAboutVersion))
                case .dependencies:
                    splitKeywords(String(localized: .settingsKeywordsAboutDependencies))
                case .developmentTools:
                    splitKeywords(String(localized: .settingsKeywordsAboutDevelopmentTools))
                case .dataSources:
                    splitKeywords(String(localized: .settingsKeywordsAboutDataSources))
            }
        }
    }
}

#if DEBUG
    extension AboutSettingsView: SnapshotProviding {
        /// Every state the screen has, which for this screen means every degree
        /// of *absence*: the shipping build is the only one that is both stamped
        /// and attributed, so the interesting cases are what each missing piece
        /// renders as.
        static var snapshots: [SnapshotCase] {
            whereSnapshot(
                name: "Default",
                configurations: .fullContentScreenDefaults,
                measurementReadiness: .immediate,
                // The navigation bar's scroll-edge shadow adapts after the
                // form reaches its full-content height. Wait through that
                // otherwise quiet transition before accessibility annotation.
                settle: .settledAtLeast(minDuration: 0.75),
            ) {
                NavigationStack {
                    AboutSettingsView(
                        focus: nil,
                        buildInfo: PreviewSupport.stampedBuildInfo(),
                        attribution: PreviewSupport.sampleAttribution(),
                    )
                }
                .environment(PreviewSupport.loadedModel())
            }
            whereSnapshot(
                name: "DirtyTree",
                configurations: .fullContentPhoneLightDark,
                measurementReadiness: .immediate,
            ) {
                NavigationStack {
                    AboutSettingsView(
                        focus: nil,
                        buildInfo: PreviewSupport.stampedBuildInfo(isDirty: true),
                        attribution: PreviewSupport.sampleAttribution(),
                    )
                }
                .environment(PreviewSupport.loadedModel())
            }
            whereSnapshot(
                name: "Unattributed",
                configurations: .fullContentPhoneLightDark,
                measurementReadiness: .immediate,
            ) {
                // What a bundle outside the app target shows: honest unknowns and
                // an explicit "no report" rather than blank rows and empty sections.
                NavigationStack {
                    AboutSettingsView(
                        focus: nil,
                        buildInfo: PreviewSupport.unstampedBuildInfo(),
                        attribution: nil,
                    )
                }
                .environment(PreviewSupport.loadedModel())
            }
            whereSnapshot(
                name: "LibrariesOnly",
                configurations: .fullContentPhoneLightDark,
                measurementReadiness: .immediate,
            ) {
                // A real report that credits nothing of one kind. Pinned as an
                // image because the failure mode is purely visual: a header and
                // footer over no rows, promising a list that isn't there.
                let libraries = PreviewSupport.sampleAttribution().credits(ofKind: .library)
                NavigationStack {
                    AboutSettingsView(
                        focus: nil,
                        buildInfo: PreviewSupport.stampedBuildInfo(),
                        attribution: AttributionManifest(credits: libraries),
                    )
                }
                .environment(PreviewSupport.loadedModel())
            }
        }
    }

    #Preview {
        AboutSettingsView.snapshotPreviews
    }
#endif

#if DEBUG
    extension AboutSettingsView: WhereFlyoverProviding {
        static let flyoverData = WhereFlyoverData.snapshots(
            AboutSettingsView.self,
            title: "About",
            routes: [
                .push(to: LicenseView.flyoverID),
            ],
        )
    }
#endif

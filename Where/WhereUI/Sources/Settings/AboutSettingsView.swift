import CreditKit
import RegionKit
import SwiftUI
import WhereCore

/// Settings drill-in for what the app *is* rather than what it does: which build
/// is running, the third-party work it is built with, and where its bundled
/// region boundaries came from.
///
/// Every fact here is vended by the module that owns it — `BuildInfo` from
/// `WhereCore`, `SoftwareCredit` from `CreditKit`, `RegionDataSource` from
/// `RegionKit` — so this screen only renders and localizes. Adding a dependency
/// or a dataset means regenerating that module's data, not editing this view.
///
/// Credits are split by `SoftwareCredit.Kind` into two sections rather than one
/// combined list, because a development tool is *not* in the binary the reader
/// is running; merging them would credit honestly but describe the app falsely.
struct AboutSettingsView: View {
    var focus: SettingsFocus?

    @Environment(\.stylesheet) private var stylesheet

    private let buildInfo: BuildInfo
    private let credits: [SoftwareCredit]
    private let dataSources: [RegionDataSource]

    /// Defaults read the live values; the parameters exist so previews and tests
    /// can render a stamped build and fixed credits, which an unstamped preview
    /// bundle can't produce on its own.
    init(
        focus: SettingsFocus?,
        buildInfo: BuildInfo = .current(bundle: .main),
        credits: [SoftwareCredit] = CreditCatalog.shared.credits,
        dataSources: [RegionDataSource] = RegionDataSource.all,
    ) {
        self.focus = focus
        self.buildInfo = buildInfo
        self.credits = credits
        self.dataSources = dataSources
    }

    var body: some View {
        SettingsFocusScope(focus: focus) {
            Form {
                versionSection
                dependenciesSection
                developmentToolsSection
                dataSourcesSection
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
        Section {
            ForEach(credits.filter { $0.kind == kind }) { credit in
                // A closure-form link, not a `SettingsRoute`: routes are the
                // top-level group vocabulary, and a leaf pushed from inside one
                // group would need its own `navigationDestination` to match.
                NavigationLink {
                    LicenseView(credit: credit)
                } label: {
                    LabeledContent(credit.name) {
                        Text(credit.version)
                    }
                }
            }
        } header: {
            Text(header)
        } footer: {
            Text(footer)
        }
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
    #Preview("Stamped build") {
        NavigationStack {
            AboutSettingsView(focus: nil, buildInfo: PreviewSupport.stampedBuildInfo())
        }
        .whereBroadwayRoot()
    }

    #Preview("Built from a dirty tree") {
        NavigationStack {
            AboutSettingsView(
                focus: nil,
                buildInfo: PreviewSupport.stampedBuildInfo(isDirty: true),
            )
        }
        .whereBroadwayRoot()
    }

    #Preview("Unstamped build") {
        // What a bundle the stamp script never ran on shows: honest unknowns
        // rather than blank rows.
        NavigationStack {
            AboutSettingsView(focus: nil, buildInfo: PreviewSupport.unstampedBuildInfo())
        }
        .whereBroadwayRoot()
    }
#endif

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
                AboutVersionSection(buildInfo: buildInfo)
                AboutCreditsSection(
                    credits: attribution?.credits(ofKind: .library) ?? [],
                    emptyMessage: emptyMessage,
                    header: String(localized: .settingsAboutDependenciesHeader),
                    footer: String(localized: .settingsAboutDependenciesFooter),
                )
                .settingsRow(Item.dependencies)
                AboutCreditsSection(
                    credits: attribution?.credits(ofKind: .developmentTool) ?? [],
                    emptyMessage: emptyMessage,
                    header: String(localized: .settingsAboutDevelopmentToolsHeader),
                    footer: String(localized: .settingsAboutDevelopmentToolsFooter),
                )
                .settingsRow(Item.developmentTools)
                AboutDataSourcesSection(dataSources: dataSources)
                AboutOpenSourceFooter()
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                    .listRowInsets(EdgeInsets())
            }
            .whereFormRoot()
        }
        .navigationTitle(String(localized: .settingsAboutHeader))
        .navigationBarTitleDisplayMode(.inline)
    }

    /// Why a section is empty, which the reader needs distinguished: no report
    /// at all means the whole build is unattributed, while an empty section of
    /// a real report means only that this kind has nothing in it.
    var emptyMessage: LocalizedStringResource {
        attribution == nil ? .settingsAboutAttributionUnavailable : .settingsAboutAttributionNone
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

private struct AboutCreditsSection: View {
    let credits: [SoftwareCredit]
    let emptyMessage: LocalizedStringResource
    let header: String
    let footer: String

    var body: some View {
        Section {
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
                    AboutLicenseLink(credit: credit)
                }
            }
        } header: {
            Text(header)
        } footer: {
            Text(footer)
        }
    }
}

private struct AboutLicenseLink: View {
    let credit: SoftwareCredit

    var body: some View {
        NavigationLink {
            LicenseView(credit: credit)
                .whereScreenBoundary()
        } label: {
            LabeledContent(credit.name) {
                Text(credit.version)
            }
        }
    }
}

private struct AboutDataSourcesSection: View {
    let dataSources: [RegionDataSource]

    var body: some View {
        Section {
            ForEach(dataSources, id: \.name) { source in
                AboutDataSourceRow(source: source)
            }
        } header: {
            Text(String(localized: .settingsAboutDataSourcesHeader))
        } footer: {
            Text(String(localized: .settingsAboutDataSourcesFooter))
        }
        .settingsRow(AboutSettingsView.Item.dataSources)
    }
}

private struct AboutDataSourceFacts: View {
    let source: RegionDataSource

    var body: some View {
        Group {
            Text(source.purposes.map(WhereFormat.regionMapKind)
                .formatted(.list(type: .and)))
            Text(WhereFormat.regionDataSourceRegionCount(source.nodes.count))
            Text(WhereFormat.regionDataSourceFidelity(source.fidelity))
            Text(WhereFormat.regionDataSourceLicense(source.license))
        }
        .foregroundStyle(.secondary)
    }
}

private struct AboutDataSourceRow: View {
    let source: RegionDataSource

    @Environment(\.stylesheet) private var stylesheet

    var body: some View {
        // Everything below the name is stacked rather than trailing-aligned: a
        // boundary set's name is long enough to wrap, and a trailing count that
        // sometimes drops to its own line reads as a different layout per row.
        VStack(alignment: .leading, spacing: stylesheet.spacing.xSmall) {
            Text(source.name)
            VStack(alignment: .leading, spacing: stylesheet.spacing.xxSmall) {
                // Only the prose is dimmed — a link tinted secondary alongside
                // it stops reading as tappable.
                AboutDataSourceFacts(source: source)
                if let url = source.sourceURL {
                    Link(WhereFormat.regionDataSourcePublisher(url), destination: url)
                }
                if let url = source.licenseURL {
                    Link(destination: url) { Text(verbatim: "Open Government Licence – Canada") }
                }
                if let url = source.obtainedFromURL {
                    Link(WhereFormat.regionDataSourceObtainedFrom(url), destination: url)
                }
            }
            .font(.caption)
        }
        .lineLimit(nil)
        .fixedSize(horizontal: false, vertical: true)
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
                configurations: .fullContentPhoneLightDarkWithAX5AndAnnotations + [
                    SnapshotConfiguration(contrast: .increased, device: .iPhoneFullContent),
                    SnapshotConfiguration(device: .iPadFullContent),
                ],
                measurementReadiness: .immediate,
                // The navigation bar's scroll-edge shadow adapts after the
                // form reaches its full-content height. Wait through that
                // otherwise quiet transition before accessibility annotation.
                settle: .settledAtLeast(minDuration: 1.5),
            ) {
                AboutSettingsSnapshot(
                    buildInfo: PreviewSupport.stampedBuildInfo(),
                    attribution: PreviewSupport.sampleAttribution(),
                )
            }
            whereSnapshot(
                name: "DirtyTree",
                configurations: .fullContentPhoneLightDark,
                measurementReadiness: .immediate,
            ) {
                AboutSettingsSnapshot(
                    buildInfo: PreviewSupport.stampedBuildInfo(isDirty: true),
                    attribution: PreviewSupport.sampleAttribution(),
                )
            }
            whereSnapshot(
                name: "Unattributed",
                configurations: .fullContentPhoneLightDark,
                measurementReadiness: .immediate,
            ) {
                // What a bundle outside the app target shows: honest unknowns and
                // an explicit "no report" rather than blank rows and empty sections.
                AboutSettingsSnapshot(
                    buildInfo: PreviewSupport.unstampedBuildInfo(),
                    attribution: nil,
                )
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
                AboutSettingsSnapshot(
                    buildInfo: PreviewSupport.stampedBuildInfo(),
                    attribution: AttributionManifest(credits: libraries),
                )
            }
        }
    }

    private struct AboutSettingsSnapshot: View {
        let buildInfo: BuildInfo
        let attribution: AttributionManifest?

        var body: some View {
            NavigationStack {
                AboutSettingsView(focus: nil, buildInfo: buildInfo, attribution: attribution)
            }
            .environment(PreviewSupport.loadedModel())
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

/// A compact passport-style sign-off linking the About screen to Where's source.
struct AboutOpenSourceFooter: View {
    static let projectURL = URL(string: "https://github.com/kyleve/Stuff")!

    @Environment(\.stylesheet) private var stylesheet
    var body: some View {
        Link(destination: Self.projectURL) {
            StampBanner(
                systemSymbol: .chevronLeftForwardslashChevronRight,
                style: stylesheet.openSourceStamp,
                showsAccessory: true,
            ) {
                AboutOpenSourceStampText()
            }
        }
        .buttonStyle(.plain)
    }
}

#if DEBUG
    #Preview("Source footer") { AboutSourceFooterPreview() }

    private struct AboutSourceFooterPreview: View {
        var body: some View {
            Form {
                AboutOpenSourceFooter()
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                    .listRowInsets(EdgeInsets())
            }
            .whereBroadwayRoot()
        }
    }
#endif

/// Keeps the source stamp's title and action together across adaptive layouts.
private struct AboutOpenSourceStampText: View {
    @Environment(\.stylesheet) private var stylesheet

    var body: some View {
        let style = stylesheet.openSourceStamp
        VStack(alignment: .leading, spacing: stylesheet.spacing.xxSmall) {
            Text(LocalizedStringResource.settingsAboutSourceTitle)
                .font(style.titleFont)
                .bold()
                .foregroundStyle(style.tint.opacity(style.ink.titleOpacity))
            Text(LocalizedStringResource.settingsAboutSourceAction)
                .font(style.detailFont)
                .foregroundStyle(style.tint.opacity(style.ink.detailOpacity))
        }
    }
}

#if DEBUG
    #Preview("Source stamp") {
        AboutOpenSourceStampText()
            .padding()
            .whereBroadwayRoot()
    }
#endif

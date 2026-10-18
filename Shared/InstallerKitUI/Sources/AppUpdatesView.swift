import InstallerKit
import SFSafeSymbols
import SnapshotKit
import SwiftUI

/// Stable integration points for a host's search anchors and section highlighting.
public enum AppUpdatesSection: Hashable {
    case check
    case changes
}

/// Shared native update page. The host owns the model, app identity, and navigation eligibility.
public struct AppUpdatesView<SectionDecoration: ViewModifier>: View {
    private let model: UpdateModel
    private let branding: AppUpdateBranding
    private let sectionDecoration: (AppUpdatesSection) -> SectionDecoration

    public init(
        model: UpdateModel,
        branding: AppUpdateBranding,
        sectionDecoration: @escaping (AppUpdatesSection) -> SectionDecoration,
    ) {
        self.model = model
        self.branding = branding
        self.sectionDecoration = sectionDecoration
    }

    public var body: some View {
        UpdatePage(model: model, branding: branding, sectionDecoration: sectionDecoration)
            .installerBroadwayRoot()
            .navigationTitle(String(localized: .installerTitle))
            .navigationBarTitleDisplayMode(.inline)
    }
}

extension AppUpdatesView where SectionDecoration == EmptyModifier {
    public init(model: UpdateModel, branding: AppUpdateBranding) {
        self.init(model: model, branding: branding, sectionDecoration: { _ in EmptyModifier() })
    }
}

/// Resolves styles beneath the public screen's root, including inside another app's Broadway tree.
private struct UpdatePage<SectionDecoration: ViewModifier>: View {
    let model: UpdateModel
    let branding: AppUpdateBranding
    let sectionDecoration: (AppUpdatesSection) -> SectionDecoration
    @State private var manualCheck: Task<Void, Never>?
    @State private var isBrowsingBuilds = false
    @Environment(\.installerStylesheet) private var stylesheet

    var body: some View {
        UpdatePageLayout {
            UpdateHero(
                branding: branding,
                channelLabel: model.installed.source.channelLabel,
            ) { installAction }
            Button {
                isBrowsingBuilds = true
            } label: {
                Label(String(localized: .installerOtherBuilds), systemSymbol: .squareStack)
                    .font(stylesheet.browser.actionFont)
                    .frame(maxWidth: .infinity, minHeight: stylesheet.browser.minimumHeight)
            }
            .buttonStyle(.bordered)
            .buttonBorderShape(.capsule)
            if case .local = model.installed.source {
                UpdateLocalBuildNotice(isInstalled: true)
            }
            if case let .failed(error, previous) = model.state {
                UpdateFailureCard(error: error, hasCachedBuilds: previous != nil)
            }
            availability
            UpdateInstalledBuild(model: model, check: checkForUpdates)
                .modifier(sectionDecoration(.check))
        }
        .sheet(isPresented: $isBrowsingBuilds) {
            UpdateBrowserView(model: model, branding: branding)
        }
        .task { await model.refresh(force: false) }
        .refreshable { await model.refresh(force: true) }
        .onDisappear {
            manualCheck?.cancel()
            manualCheck = nil
        }
    }

    @ViewBuilder private var installAction: some View {
        switch model.state.snapshot?.availability {
            case let .available(update):
                UpdateInstallLink(title: .installerInstall, release: update.release)
            case let .retired(main):
                if let main { UpdateInstallLink(title: .installerSwitchMain, release: main) }
            case .current:
                Label(String(localized: .installerCurrent), systemSymbol: .checkmarkCircle)
                    .font(stylesheet.hero.subtitleFont)
            case .local, .unpublished, nil:
                EmptyView()
        }
    }

    @ViewBuilder private var availability: some View {
        switch model.state.snapshot?.availability {
            case let .available(update):
                UpdateBuildSummary(release: update.release)
                UpdateChanges(changes: update.changes, installed: model.installed)
                    .modifier(sectionDecoration(.changes))
                UpdateBuildInformation(release: update.release, installed: model.installed)
            case let .retired(main):
                UpdateCard(title: .installerRetiredTitle) {
                    Text(main == nil ? LocalizedStringResource
                        .installerRetiredUnavailable : .installerRetiredMessage)
                        .font(stylesheet.card.bodyFont)
                        .foregroundStyle(.secondary)
                }
                if let main {
                    UpdateBuildSummary(release: main, title: .installerMainBuild)
                    UpdateBuildInformation(release: main, installed: model.installed)
                }
            case .unpublished:
                UpdateCard(title: .installerNoPublishedBuild) {
                    Text(.installerUnpublished)
                        .font(stylesheet.card.bodyFont)
                        .foregroundStyle(.secondary)
                }
            case .local, .current, nil:
                EmptyView()
        }
    }

    private func checkForUpdates() {
        manualCheck?.cancel()
        manualCheck = Task { await model.refresh(force: true) }
    }
}

#if DEBUG
    extension AppUpdatesView: SnapshotProviding where SectionDecoration == EmptyModifier {
        public static var snapshots: [SnapshotCase] {
            for scenario in InstallerPreview.Scenario.allCases {
                let model = InstallerPreview.model(scenario)
                SnapshotCase(
                    name: scenario.rawValue,
                    configurations: scenario == .available || scenario == .local ?
                        .fullContentScreenDefaults :
                        SnapshotConfiguration.combinations(
                            devices: [.iPhoneFullContent],
                            colorSchemes: [.light, .dark],
                        ),
                    measurementReadiness: scenario.requiresRefresh ? .sameAsCapture : .immediate,
                    onReadyToMeasure: {
                        if scenario.requiresRefresh { await model.refresh(force: true) }
                    },
                ) {
                    NavigationStack { AppUpdatesView(
                        model: model,
                        branding: InstallerPreview.branding,
                    ) }
                }
            }
        }
    }

    #Preview { AppUpdatesView<EmptyModifier>.snapshotPreviews }
#endif

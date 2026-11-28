import InstallerKit
import SFSafeSymbols
import SwiftUI

/// Resolves styles beneath the public screen's root, including inside another app's Broadway tree.
struct UpdatePage<SectionDecoration: ViewModifier>: View {
    let model: UpdateModel
    let branding: AppUpdateBranding
    let sectionDecoration: (AppUpdatesSection) -> SectionDecoration
    @State private var refresh = UpdatePageRefresh()
    @State private var isBrowsingBuilds = false

    var body: some View {
        UpdatePageLayout {
            UpdateHero(
                branding: branding,
                channelLabel: model.installed.source.channelLabel,
            ) {
                UpdateInstallAction(availability: model.state.snapshot?.availability)
            }
            OtherBuildsButton { isBrowsingBuilds = true }
            if case .local = model.installed.source {
                UpdateLocalBuildNotice(isInstalled: true)
            }
            if case let .failed(error, previous) = model.state {
                UpdateFailureCard(error: error, hasCachedBuilds: previous != nil)
            }
            UpdateAvailabilitySections(
                availability: model.state.snapshot?.availability,
                installed: model.installed,
                sectionDecoration: sectionDecoration,
            )
            UpdateInstalledBuild(model: model, check: { refresh.start(model: model) })
                .modifier(sectionDecoration(.check))
        }
        .sheet(isPresented: $isBrowsingBuilds) {
            UpdateBrowserView(model: model, branding: branding)
        }
        .task { await model.refresh(force: false) }
        .refreshable { await refresh.start(model: model).value }
        .onDisappear { refresh.cancel() }
    }
}

private struct UpdateInstallAction: View {
    let availability: UpdateCatalog.Availability?
    @Environment(\.installerStylesheet) private var stylesheet

    var body: some View {
        switch availability {
            case let .available(update):
                UpdateInstallLink(title: .installerInstall, release: update.release)
            case let .retired(main):
                if let main {
                    UpdateInstallLink(title: .installerSwitchMain, release: main)
                }
            case .current:
                Label(String(localized: .installerCurrent), systemSymbol: .checkmarkCircle)
                    .font(stylesheet.hero.subtitleFont)
            case .local, .unpublished, nil:
                EmptyView()
        }
    }
}

private struct OtherBuildsButton: View {
    let openBrowser: () -> Void
    @Environment(\.installerStylesheet) private var stylesheet

    var body: some View {
        Button(action: openBrowser) {
            Label(String(localized: .installerOtherBuilds), systemSymbol: .squareStack)
                .font(stylesheet.browser.actionFont)
                .frame(maxWidth: .infinity, minHeight: stylesheet.browser.minimumHeight)
        }
        .buttonStyle(.bordered)
        .buttonBorderShape(.capsule)
    }
}

#if DEBUG
    #Preview { AppUpdatesView<EmptyModifier>.snapshotPreviews }
#endif

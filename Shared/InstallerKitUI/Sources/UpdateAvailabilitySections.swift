import InstallerKit
import SwiftUI

struct UpdateAvailabilitySections<SectionDecoration: ViewModifier>: View {
    let availability: UpdateCatalog.Availability?
    let installed: InstalledBuild
    let sectionDecoration: (AppUpdatesSection) -> SectionDecoration

    var body: some View {
        switch availability {
            case let .available(update):
                UpdateBuildSummary(release: update.release)
                UpdateChanges(changes: update.changes, installed: installed)
                    .modifier(sectionDecoration(.changes))
                UpdateBuildInformation(
                    channel: update.channel,
                    release: update.release,
                    installed: installed,
                )
            case let .retired(main):
                UpdateAvailabilityNotice(
                    title: .installerRetiredTitle,
                    message: main == nil ? .installerRetiredUnavailable : .installerRetiredMessage,
                )
                if let main {
                    UpdateBuildSummary(release: main, title: .installerMainBuild)
                    UpdateBuildInformation(
                        channel: .main,
                        release: main,
                        installed: installed,
                    )
                }
            case .unpublished:
                UpdateAvailabilityNotice(
                    title: .installerNoPublishedBuild,
                    message: .installerUnpublished,
                )
            case .local, .current, nil:
                EmptyView()
        }
    }
}

private struct UpdateAvailabilityNotice: View {
    let title: LocalizedStringResource
    let message: LocalizedStringResource
    @Environment(\.installerStylesheet) private var stylesheet

    var body: some View {
        UpdateCard(title: title) {
            Text(message)
                .font(stylesheet.card.bodyFont)
                .foregroundStyle(.secondary)
        }
    }
}

#if DEBUG
    #Preview { AppUpdatesView<EmptyModifier>.snapshotPreviews }
#endif

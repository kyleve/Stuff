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
                UpdateNoticeCard(
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
                UpdateNoticeCard(
                    title: .installerNoPublishedBuild,
                    message: .installerUnpublished,
                )
            case .local, .current, nil:
                EmptyView()
        }
    }
}

#if DEBUG
    #Preview { AppUpdatesView<EmptyModifier>.snapshotPreviews }
#endif

import InstallerKit
#if DEBUG
    @_spi(Testing) import InstallerKitUI
    import SnapshotKit
#else
    import InstallerKitUI
#endif
import SwiftUI

/// Throw's branding wrapper around the shared InstallerKit update screen.
struct ThrowUpdatesView: View {
    let model: UpdateModel

    var body: some View {
        AppUpdatesView(
            model: model,
            branding: AppUpdateBranding(
                name: String(localized: .updatesAppName),
                subtitle: String(localized: .updatesSubtitle),
            ),
        )
    }
}

#if DEBUG
    extension ThrowUpdatesView: SnapshotProviding {
        static var snapshots: [SnapshotCase] {
            let model = InstallerPreview.model(.available)
            return [
                SnapshotCase(
                    name: "Available",
                    configurations: [SnapshotConfiguration(device: .iPhoneFullContent)],
                    measurementReadiness: .immediate,
                ) {
                    NavigationStack { ThrowUpdatesView(model: model) }
                        .throwBroadwayRoot()
                },
            ]
        }
    }

    #Preview {
        ThrowUpdatesView.snapshotPreviews
    }
#endif

import InstallerKit
import SnapshotKit
import SwiftUI

/// The same failure details appear on the update page and every build-browser destination.
struct UpdateFailureCard: View {
    let error: any Error
    let hasCachedBuilds: Bool
    @Environment(\.installerStylesheet) private var stylesheet

    var body: some View {
        let description = UpdateFailureDescription(error: error)
        UpdateCard(title: .installerCheckFailed) {
            Text(verbatim: description.message)
                .font(stylesheet.card.bodyFont)
            Text(verbatim: description.code)
                .font(stylesheet.failure.codeFont)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
            if hasCachedBuilds {
                Text(.installerFailureCachedBuilds)
                    .font(stylesheet.card.bodyFont)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

#if DEBUG
    extension UpdateFailureCard: SnapshotProviding {
        static var snapshots: [SnapshotCase] {
            // OfflineCached owns text scaling and VoiceOver annotation coverage.
            // The standalone cards render fixed error values and have no refresh to await.
            SnapshotCase(
                name: "MissingFeed",
                configurations: .componentLightDark,
                settle: .immediate,
            ) {
                UpdateFailureCard(
                    error: UpdateClient.FetchError.httpStatus(404),
                    hasCachedBuilds: false,
                )
                .background(InstallerStylesheet.default.page.background)
                .installerBroadwayRoot()
            }
            SnapshotCase(
                name: "OfflineCached",
                configurations: .componentRepresentative,
                settle: .immediate,
            ) {
                UpdateFailureCard(
                    error: URLError(.notConnectedToInternet),
                    hasCachedBuilds: true,
                )
                .background(InstallerStylesheet.default.page.background)
                .installerBroadwayRoot()
            }
        }
    }

    #Preview { UpdateFailureCard.snapshotPreviews }
#endif

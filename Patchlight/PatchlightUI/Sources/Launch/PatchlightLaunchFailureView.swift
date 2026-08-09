import LifecycleKit
import SwiftUI

struct PatchlightLaunchFailureView: View {
    let failure: LifecycleFailure

    var body: some View {
        ContentUnavailableView {
            Label(
                String(localized: .couldNotOpenPatchlight),
                systemImage: "exclamationmark.triangle",
            )
        } description: {
            Text(failure.error.localizedDescription)
        } actions: {
            Text(String(localized: .relaunchToTryAgain))
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }
}

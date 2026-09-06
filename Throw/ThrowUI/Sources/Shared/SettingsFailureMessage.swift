import SFSafeSymbols
import SwiftUI

struct SettingsFailureMessage: View {
    let failure: ThrowPostLaunchFailure

    var body: some View {
        Label {
            VStack(alignment: .leading, spacing: 4) {
                Text(.settingsFailureTitle)
                    .font(.headline)
                Text(failure.userMessage)
                    .font(.footnote)
            }
        } icon: {
            Image(systemSymbol: .exclamationmarkTriangleFill)
        }
        .foregroundStyle(.red)
        .accessibilityElement(children: .combine)
    }
}

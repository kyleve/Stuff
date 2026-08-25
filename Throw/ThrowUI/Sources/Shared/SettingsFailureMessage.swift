import SFSafeSymbols
import SwiftUI

struct SettingsFailureMessage: View {
    let detail: String

    var body: some View {
        Label {
            VStack(alignment: .leading, spacing: 4) {
                Text(.settingsFailureTitle)
                    .font(.headline)
                Text(verbatim: detail)
                    .font(.footnote)
            }
        } icon: {
            Image(systemSymbol: .exclamationmarkTriangleFill)
        }
        .foregroundStyle(.red)
        .accessibilityElement(children: .combine)
    }
}

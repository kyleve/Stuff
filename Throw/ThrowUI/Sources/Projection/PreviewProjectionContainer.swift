import SFSafeSymbols
import SwiftUI

struct PreviewProjectionContainer: View {
    let session: ThrowSession
    let outputID: ProjectionOutputID
    let onExit: () -> Void

    var body: some View {
        PreviewProjectionView(session: session, outputID: outputID)
            .overlay(alignment: .topTrailing) {
                Button(String(localized: .commonDone), systemSymbol: .xmark, action: onExit)
                    .buttonStyle(.borderedProminent)
                    .tint(.black.opacity(0.7))
                    .padding()
            }
            .accessibilityAddTraits(.isModal)
    }
}

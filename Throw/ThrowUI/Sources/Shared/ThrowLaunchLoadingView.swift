import SFSafeSymbols
import SwiftUI

struct ThrowLaunchLoadingView: View {
    var body: some View {
        VStack {
            Image(systemSymbol: .hourglass)
                .font(.title3)
                .accessibilityHidden(true)
            Text(.statusLoading)
        }
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

import SFSafeSymbols
import SwiftUI

struct UpdateCheckButton: View {
    let isChecking: Bool
    let check: () -> Void
    @Environment(\.installerStylesheet) private var stylesheet

    var body: some View {
        Button(action: check) {
            Label(
                String(localized: isChecking ? .installerChecking : .installerCheck),
                systemSymbol: .arrowClockwise,
            )
            .font(stylesheet.check.font)
            .frame(maxWidth: .infinity, minHeight: stylesheet.check.minimumHeight)
        }
        .disabled(isChecking)
        .buttonStyle(.bordered)
        .buttonBorderShape(.capsule)
    }
}

#if DEBUG
    #Preview { AppUpdatesView<EmptyModifier>.snapshotPreviews }
#endif

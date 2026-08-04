#if DEBUG
    import SwiftUI

    /// Presents Flyover outside Developer Tools' navigation domain.
    struct WhereFlyoverPresentationView: View {
        @Environment(\.dismiss) private var dismiss

        var body: some View {
            WhereFlyoverView()
                .overlay(alignment: .topLeading) {
                    Button(
                        String(localized: .developerClose),
                        systemImage: "xmark",
                        action: dismiss.callAsFunction,
                    )
                    .labelStyle(.iconOnly)
                    .buttonStyle(.bordered)
                    .buttonBorderShape(.circle)
                    .padding()
                }
        }
    }

    #Preview {
        WhereFlyoverPresentationView()
    }
#endif

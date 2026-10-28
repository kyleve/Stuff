#if DEBUG
    import SwiftUI

    struct CardDesignerSectionHeader: View {
        let title: LocalizedStringResource
        let reset: () -> Void

        var body: some View {
            HStack {
                Text(title)
                Spacer()
                Button(String(localized: .cardDesignerReset), action: reset)
                    .textCase(nil)
                    .font(.caption)
            }
        }
    }

    #Preview {
        Form {
            Section {} header: {
                CardDesignerSectionHeader(title: .cardDesignerTypography, reset: {})
            }
        }
    }
#endif

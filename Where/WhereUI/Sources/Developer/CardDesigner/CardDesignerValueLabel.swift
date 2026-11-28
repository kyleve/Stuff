#if DEBUG
    import SwiftUI

    struct CardDesignerValueLabel: View {
        let title: LocalizedStringResource
        let value: Double

        var body: some View {
            LabeledContent {
                Text(value, format: .number.precision(.fractionLength(0 ... 4)))
                    .monospacedDigit()
            } label: {
                Text(title)
            }
        }
    }

    #Preview { CardDesignerValueLabel(title: .cardDesignerOpacity, value: 0.65) }
#endif

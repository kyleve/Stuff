#if DEBUG
    import SwiftUI

    struct CardDesignerDoubleControl: View {
        let title: LocalizedStringResource
        @Binding var value: Double
        let range: ClosedRange<Double>
        let step: Double

        var body: some View {
            VStack(alignment: .leading, spacing: 6) {
                LabeledContent {
                    Text(value, format: .number.precision(.fractionLength(0 ... 4)))
                        .monospacedDigit()
                } label: {
                    Text(title)
                }
                Slider(value: $value, in: range, step: step)
            }
            .onChange(of: value) { _, newValue in
                value = min(range.upperBound, max(range.lowerBound, newValue))
            }
        }
    }
#endif

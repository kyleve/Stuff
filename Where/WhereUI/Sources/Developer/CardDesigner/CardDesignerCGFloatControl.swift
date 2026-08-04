#if DEBUG
    import SwiftUI

    struct CardDesignerCGFloatControl: View {
        let title: LocalizedStringResource
        @Binding var value: CGFloat
        let range: ClosedRange<CGFloat>
        let step: CGFloat

        var body: some View {
            VStack(alignment: .leading, spacing: 6) {
                LabeledContent {
                    Text(Double(value), format: .number.precision(.fractionLength(0 ... 4)))
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

    #Preview {
        @Previewable @State var value: CGFloat = 28
        Form {
            CardDesignerCGFloatControl(
                title: .cardDesignerCornerRadius,
                value: $value,
                range: 0 ... 60,
                step: 1,
            )
        }
    }
#endif

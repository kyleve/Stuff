import SwiftUI

/// A standard Flyover stepper whose value label stays live with its binding.
struct FlyoverStepperControl: View {
    let title: String
    @Binding var value: Int
    let bounds: ClosedRange<Int>

    var body: some View {
        Stepper(value: $value, in: bounds) {
            LabeledContent(title, value: value.formatted())
        }
    }
}

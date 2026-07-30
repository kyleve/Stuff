import SwiftUI

/// A typed control rendered below a Flyover screen.
@MainActor
public struct FlyoverControl {
    public let id: AnyHashable
    let content: AnyView

    public init(
        id: some Hashable,
        @ViewBuilder content: () -> some View,
    ) {
        self.id = AnyHashable(id)
        self.content = AnyView(content())
    }

    public static func toggle(
        id: some Hashable,
        title: String,
        isOn: Binding<Bool>,
    ) -> FlyoverControl {
        FlyoverControl(id: id) {
            Toggle(title, isOn: isOn)
        }
    }

    public static func slider(
        id: some Hashable,
        title: String,
        value: Binding<Double>,
        in bounds: ClosedRange<Double>,
        step: Double? = nil,
    ) -> FlyoverControl {
        FlyoverControl(id: id) {
            LabeledContent(title) {
                if let step {
                    Slider(value: value, in: bounds, step: step)
                } else {
                    Slider(value: value, in: bounds)
                }
            }
        }
    }

    public static func stepper(
        id: some Hashable,
        title: String,
        value: Binding<Int>,
        in bounds: ClosedRange<Int>,
    ) -> FlyoverControl {
        FlyoverControl(id: id) {
            FlyoverStepperControl(title: title, value: value, bounds: bounds)
        }
    }

    public static func picker<Selection: Hashable, Values: RandomAccessCollection>(
        id: some Hashable,
        title: String,
        selection: Binding<Selection>,
        values: Values,
        label: @escaping @MainActor (Selection) -> String,
    ) -> FlyoverControl where Values.Element == Selection {
        FlyoverControl(id: id) {
            Picker(title, selection: selection) {
                ForEach(Array(values), id: \.self) { value in
                    Text(label(value))
                        .tag(value)
                }
            }
        }
    }

    public static func action(
        id: some Hashable,
        title: String,
        systemImage: String,
        action: @escaping @MainActor () -> Void,
    ) -> FlyoverControl {
        FlyoverControl(id: id) {
            Button(title, systemImage: systemImage, action: action)
        }
    }
}

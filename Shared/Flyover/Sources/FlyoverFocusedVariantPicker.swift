import SwiftUI

/// The selected variant control in the focused inspector.
struct FlyoverFocusedVariantPicker<ScreenID: Hashable>: View {
    let screen: FlyoverScreen<ScreenID>
    let model: FlyoverModel<ScreenID>

    var body: some View {
        @Bindable var state = model.state(for: screen)

        if screen.variants.count > 1 {
            Picker("Variant", selection: $state.variantID) {
                ForEach(screen.variants, id: \.id) { variant in
                    Text(variant.title)
                        .tag(variant.id)
                }
            }
            .pickerStyle(.menu)
        }
    }
}

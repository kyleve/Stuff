import SwiftUI

/// Color and accessibility trait controls for registered Flyover content.
struct FlyoverAppearanceMenu<ScreenID: Hashable>: View {
    @Bindable var model: FlyoverModel<ScreenID>

    var body: some View {
        Menu("Traits", systemImage: "circle.lefthalf.filled") {
            Picker("Appearance", selection: $model.appearance) {
                ForEach(FlyoverAppearance.allCases) { appearance in
                    Text(appearance.title)
                        .tag(appearance)
                }
            }
            Picker("Dynamic Type", selection: $model.dynamicType) {
                ForEach(FlyoverDynamicType.allCases) { size in
                    Text(size.title)
                        .tag(size)
                }
            }
            Picker("Contrast", selection: $model.contrast) {
                Text("Standard")
                    .tag(ColorSchemeContrast.standard)
                Text("Increased")
                    .tag(ColorSchemeContrast.increased)
            }
            Picker("Layout Direction", selection: $model.layoutDirection) {
                Text("Left to Right")
                    .tag(LayoutDirection.leftToRight)
                Text("Right to Left")
                    .tag(LayoutDirection.rightToLeft)
            }
            Picker("Text Weight", selection: $model.legibilityWeight) {
                Text("Regular")
                    .tag(LegibilityWeight.regular)
                Text("Bold")
                    .tag(LegibilityWeight.bold)
            }
        }
    }
}

import SFSafeSymbols
import SwiftUI

/// Color and accessibility trait controls for registered Flyover content.
struct FlyoverAppearanceMenu<ScreenID: Hashable>: View {
    @Bindable var model: FlyoverModel<ScreenID>

    var body: some View {
        Menu {
            FlyoverOptionsPicker(
                title: "Appearance",
                choices: FlyoverAppearance.allCases,
                selection: $model.appearance,
                label: \.title,
            )
            FlyoverOptionsPicker(
                title: "Dynamic Type",
                choices: FlyoverDynamicType.allCases,
                selection: $model.dynamicType,
                label: \.title,
            )
            FlyoverContrastPicker(selection: $model.contrast)
            FlyoverDirectionPicker(selection: $model.layoutDirection)
            FlyoverWeightPicker(selection: $model.legibilityWeight)
        } label: {
            Label("Traits", systemSymbol: .circleLefthalfFilled)
        }
    }
}

private struct FlyoverContrastPicker: View {
    @Binding var selection: ColorSchemeContrast

    var body: some View {
        Picker("Contrast", selection: $selection) {
            Text("Standard")
                .tag(ColorSchemeContrast.standard)
            Text("Increased")
                .tag(ColorSchemeContrast.increased)
        }
    }
}

private struct FlyoverDirectionPicker: View {
    @Binding var selection: LayoutDirection

    var body: some View {
        Picker("Layout Direction", selection: $selection) {
            Text("Left to Right")
                .tag(LayoutDirection.leftToRight)
            Text("Right to Left")
                .tag(LayoutDirection.rightToLeft)
        }
    }
}

private struct FlyoverWeightPicker: View {
    @Binding var selection: LegibilityWeight

    var body: some View {
        Picker("Text Weight", selection: $selection) {
            Text("Regular")
                .tag(LegibilityWeight.regular)
            Text("Bold")
                .tag(LegibilityWeight.bold)
        }
    }
}

#if DEBUG
    #Preview {
        FlyoverView(catalog: FlyoverPreview.catalog)
    }
#endif

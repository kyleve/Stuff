#if DEBUG
    import SwiftUI

    struct CardDesignerMicroprintControls: View {
        @Binding var border: CardDesignerConfiguration.SecurityBorder

        var body: some View {
            CardDesignerCGFloatControl(
                title: .cardDesignerInset,
                value: $border.inset,
                range: 0 ... 30,
                step: 0.5,
            )
            CardDesignerCGFloatControl(
                title: .cardDesignerGlyphSize,
                value: $border.glyphSize,
                range: 2 ... 24,
                step: 0.5,
            )
            CardDesignerCGFloatControl(
                title: .cardDesignerSpacing,
                value: $border.spacing,
                range: 2 ... 32,
                step: 0.5,
            )
            CardDesignerDoubleControl(
                title: .cardDesignerOpacity,
                value: $border.opacity,
                range: 0 ... 1,
                step: 0.01,
            )
        }
    }
#endif

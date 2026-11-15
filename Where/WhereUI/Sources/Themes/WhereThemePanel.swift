import SwiftUI

/// Shared paper treatment for native calendar, timeline, and section content.
private struct WhereThemePanel<Shape: InsettableShape, NativeBackground: View>: ViewModifier {
    let role: WhereThemeComponents.Role
    let shape: Shape
    let tint: Color
    let nativeBackground: NativeBackground
    @Environment(\.whereComponentStylesheet) private var stylesheet

    func body(content: Content) -> some View {
        let style = stylesheet[role]
        if style.surface != nil || style.background != nil || !style.artworkOpacity.isEmpty {
            content.modifier(WhereComponentSurface(
                role: role,
                shape: shape,
                finish: WherePaperFinish(surface: style.surface, tint: tint, shape: shape),
            ) { nativeBackground })
        } else {
            content.modifier(WhereComponentTextStyle(role: role)).background { nativeBackground }
        }
    }
}

private struct WherePaperFinish<Shape: InsettableShape>: ViewModifier {
    let surface: WhereStylesheet.SurfaceTreatment?
    let tint: Color
    let shape: Shape
    func body(content: Content) -> some View {
        switch surface {
            case .none: content
            case .some(.reflective):
                content
                    .background { shape.fill(.clear).glassEffect(
                        .regular,
                        in: shape,
                    ) }
                    .clipShape(shape)
                    .contentShape(shape)
            case let .some(.matte(paper)):
                content.matteSurface(.matte(paper), tint: tint, in: shape)
        }
    }
}

private struct WhereThemeListRow: ViewModifier {
    @Environment(\.whereComponentStylesheet) private var stylesheet
    func body(content: Content) -> some View {
        if stylesheet[.section].background != nil || !stylesheet[.section].artworkOpacity.isEmpty {
            content
                .modifier(WhereComponentTextStyle(role: .section))
                .listRowBackground(WhereThemeRowBackground())
        } else { content.modifier(WhereComponentTextStyle(role: .section)) }
    }
}

/// List owns row clipping and interaction. Documents can paint only the row interior.
struct WhereThemeRowBackground: View {
    @Environment(\.whereComponentStylesheet) private var stylesheet
    var body: some View {
        (stylesheet[.section].background ?? Color(.secondarySystemGroupedBackground))
            .overlay { WhereComponentArtwork(role: .section, plane: .interior, shape: Rectangle()) }
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}

extension View {
    func whereThemeListRow() -> some View {
        modifier(WhereThemeListRow())
    }

    func whereThemePanel(
        _ role: WhereThemeComponents.Role,
        in shape: some InsettableShape,
        tint: Color = .primary,
    ) -> some View {
        modifier(WhereThemePanel(
            role: role,
            shape: shape,
            tint: tint,
            nativeBackground: EmptyView(),
        ))
    }

    func whereThemePanel(
        _ role: WhereThemeComponents.Role,
        in shape: some InsettableShape,
        tint: Color,
        @ViewBuilder background: () -> some View,
    ) -> some View {
        modifier(WhereThemePanel(
            role: role,
            shape: shape,
            tint: tint,
            nativeBackground: background(),
        ))
    }
}

#if DEBUG
    #Preview("Theme row") {
        WhereThemeRowBackground().frame(height: 52).whereBroadwayRoot()
    }
#endif

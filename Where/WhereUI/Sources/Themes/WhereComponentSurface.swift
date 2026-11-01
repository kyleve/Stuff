import BroadwayUI
import SwiftUI
import ViewDocumentCore
import ViewDocumentUI

extension EnvironmentValues {
    @Entry var whereThemeDocument: PreparedWhereThemeDocument?
    @Entry var whereThemeLayersAreActive = true
    @Entry var whereThemeSecondaryInk: Color?
}

/// One composition path for native content with interior and bounded exterior theme artwork.
struct WhereComponentSurface<
    Shape: InsettableShape,
    Finish: ViewModifier,
    NativeBackground: View,
>: ViewModifier {
    let role: WhereThemeComponents.Role
    let shape: Shape
    let finish: Finish
    let nativeBackground: NativeBackground
    @Environment(\.whereComponentStylesheet) private var stylesheet

    init(
        role: WhereThemeComponents.Role,
        shape: Shape,
        finish: Finish,
        @ViewBuilder background: () -> NativeBackground,
    ) {
        self.role = role
        self.shape = shape
        self.finish = finish
        nativeBackground = background()
    }

    init(role: WhereThemeComponents.Role, shape: Shape, finish: Finish)
        where NativeBackground == EmptyView
    {
        self.init(role: role, shape: shape, finish: finish) { EmptyView() }
    }

    func body(content: Content) -> some View {
        BSurface(shape: shape, finish: finish) {
            ZStack {
                if let background = stylesheet[role].background { shape.fill(background) }
                nativeBackground
            }
        } interior: {
            WhereComponentArtwork(role: role, plane: .interior, shape: shape)
        } content: {
            content.modifier(WhereComponentTextStyle(role: role))
        } highlights: {
            EmptyView()
        } exterior: {
            WhereComponentArtwork(role: role, plane: .exterior, shape: shape)
        }
    }
}

/// Supplies document defaults while explicit data and control styles remain native.
struct WhereComponentTextStyle: ViewModifier {
    let role: WhereThemeComponents.Role
    @Environment(\.whereComponentStylesheet) private var stylesheet

    func body(content: Content) -> some View {
        let style = stylesheet[role]
        if let foreground = style.foreground {
            typography(content)
                .foregroundStyle(foreground)
                .environment(\.whereThemeSecondaryInk, style.secondaryForeground)
        } else { typography(content) }
    }

    @ViewBuilder private func typography(_ content: Content) -> some View {
        let style = stylesheet[role]
        if let font = style.body { content.font(font).fontDesign(style.bodyDesign) }
        else { content }
    }
}

struct WhereComponentArtwork<Shape: InsettableShape>: View {
    let role: WhereThemeComponents.Role
    let plane: ViewArtworkPlacement.Plane
    let shape: Shape
    @Environment(\.whereThemeDocument) private var theme
    @Environment(\.whereComponentStylesheet) private var stylesheet
    @Environment(\.whereThemeLayersAreActive) private var hostIsActive
    @Environment(\.scenePhase) private var scenePhase
    @MotionIsStatic private var motionIsStatic
    @State private var isVisible = false

    var body: some View {
        ZStack {
            ForEach(theme?.componentArtwork[role] ?? []) { artwork in
                if artwork.placement.value.plane == plane,
                   let opacity = stylesheet[role].artworkOpacity[artwork.id]
                {
                    BArtworkLayer(
                        placement: artwork.placement,
                        shape: shape,
                        role: artwork.role,
                        maximumOutsets: .init(
                            top: stylesheet[role].outsets.top,
                            leading: stylesheet[role].outsets.leading,
                            bottom: stylesheet[role].outsets.bottom,
                            trailing: stylesheet[role].outsets.trailing,
                        ),
                    ) {
                        BViewDocumentLayer(
                            document: artwork.document,
                            isActive: isVisible && hostIsActive && scenePhase == .active,
                            motionIsStatic: motionIsStatic,
                            role: artwork.role,
                        )
                    }
                    .opacity(opacity)
                }
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .onScrollVisibilityChange(threshold: 0.01) { isVisible = $0 }
        .onAppear { isVisible = true }
        .onDisappear { isVisible = false }
    }
}

/// A descendant cannot reactivate motion when an ancestor is covered or on another tab.
private struct WhereThemeActivity: ViewModifier {
    let active: Bool
    @Environment(\.whereThemeLayersAreActive) private var parentIsActive
    func body(content: Content) -> some View {
        content.environment(\.whereThemeLayersAreActive, parentIsActive && active)
    }
}

extension View {
    func whereThemeActivity(_ active: Bool)
        -> some View
    {
        modifier(WhereThemeActivity(active: active))
    }
}

#if DEBUG
    #Preview("Component surface") {
        Text("Native content")
            .padding(40)
            .modifier(WhereComponentSurface(
                role: .regularCard,
                shape: RoundedRectangle(cornerRadius: 20),
                finish: EmptyModifier(),
            ))
            .padding(40)
            .whereBroadwayRoot()
    }
#endif

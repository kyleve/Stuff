import SFSafeSymbols
import SwiftUI

/// A full-screen, live inspector for one registered screen.
struct FlyoverFocusedView<ScreenID: Hashable>: View {
    let screen: FlyoverScreen<ScreenID>
    let model: FlyoverModel<ScreenID>
    @Environment(\.dismiss) private var dismiss
    @Environment(\.flyoverStylesheet) private var stylesheet

    var body: some View {
        NavigationStack {
            ScrollView([.horizontal, .vertical]) {
                FlyoverScreenContent(
                    screen: screen,
                    model: model,
                    isOverview: false,
                )
                .padding(stylesheet.focused.contentPadding)
            }
            .background(stylesheet.canvas.background)
            .navigationTitle(screen.title)
            .navigationBarTitleDisplayMode(.inline)
            .safeAreaInset(edge: .bottom, spacing: 0) {
                FlyoverFocusedControls(screen: screen, model: model)
            }
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done", action: dismiss.callAsFunction)
                }
            }
        }
    }
}

/// Local controls repeated beneath a focused, interactive screen.
private struct FlyoverFocusedControls<ScreenID: Hashable>: View {
    let screen: FlyoverScreen<ScreenID>
    let model: FlyoverModel<ScreenID>
    @Environment(\.flyoverStylesheet) private var stylesheet

    var body: some View {
        ScrollView(.horizontal) {
            HStack(spacing: stylesheet.controlBar.focusedSpacing) {
                FlyoverVariantPicker(screen: screen, model: model)

                ForEach(screen.controls, id: \.id) { control in
                    control.content
                        .frame(minWidth: stylesheet.controlBar.focusedControlMinimumWidth)
                }

                if let customControls = screen.customControls {
                    customControls
                }

                Button("Reset", systemSymbol: .arrowCounterclockwise) {
                    model.reset(screen)
                }
            }
            .padding(.horizontal, stylesheet.controlBar.horizontalPadding)
            .padding(.vertical, stylesheet.controlBar.verticalPadding)
        }
        .flyoverBarSurface()
    }
}

#if DEBUG
    #Preview {
        FlyoverView(catalog: FlyoverPreview.catalog)
    }
#endif

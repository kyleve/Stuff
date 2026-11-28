import SFSafeSymbols
import SwiftUI

/// Flyover's Broadway-rooted content and presentation routing.
struct FlyoverRootView<ScreenID: Hashable>: View {
    let catalog: FlyoverCatalog<ScreenID>
    @Bindable var model: FlyoverModel<ScreenID>
    @Environment(\.flyoverStylesheet) private var stylesheet

    var body: some View {
        Group {
            if catalog.isValid {
                FlyoverOverview(catalog: catalog, model: model)
            } else {
                ContentUnavailableView(
                    "Invalid Flyover Catalog",
                    systemSymbol: .exclamationmarkTriangle,
                    description: Text(
                        "\(catalog.validationIssues.count) structural issue(s) must be fixed.",
                    ),
                )
            }
        }
        .background(stylesheet.canvas.background)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if catalog.isValid {
                FlyoverControlBar(catalog: catalog, model: model)
            }
        }
        .fullScreenCover(item: $model.focusedSelection) { selection in
            if let screen = catalog.screen(id: selection.id) {
                FlyoverFocusedView(screen: screen, model: model)
            }
        }
    }
}

/// Switches between Flyover's graph canvas and linear list.
struct FlyoverOverview<ScreenID: Hashable>: View {
    let catalog: FlyoverCatalog<ScreenID>
    let model: FlyoverModel<ScreenID>

    var body: some View {
        switch model.viewMode {
            case .canvas:
                FlyoverCanvasView(catalog: catalog, model: model)
            case .list:
                FlyoverListView(catalog: catalog, model: model)
        }
    }
}

/// Session-only controls that change the presentation traits of every frame.
struct FlyoverControlBar<ScreenID: Hashable>: View {
    let catalog: FlyoverCatalog<ScreenID>
    @Bindable var model: FlyoverModel<ScreenID>
    @Environment(\.flyoverStylesheet) private var stylesheet

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: stylesheet.controlBar.wideSpacing) {
                FlyoverViewModePicker(model: model)
                    .frame(width: stylesheet.controlBar.wideViewModeWidth)
                FlyoverZoomSlider(model: model)
                    .frame(width: stylesheet.controlBar.wideZoomWidth)
                FlyoverViewportMenu(model: model)
                FlyoverAppearanceMenu(model: model)
                FlyoverResetAllButton(iconOnly: false, reset: resetAll)
            }

            FlyoverCompactControlBar(catalog: catalog, model: model)
        }
        .padding(.horizontal, stylesheet.controlBar.horizontalPadding)
        .padding(.vertical, stylesheet.controlBar.verticalPadding)
        .flyoverBarSurface()
    }

    private func resetAll() {
        model.resetAll(catalog)
    }
}

/// A width-constrained bottom bar that preserves every global control.
private struct FlyoverCompactControlBar<ScreenID: Hashable>: View {
    let catalog: FlyoverCatalog<ScreenID>
    @Bindable var model: FlyoverModel<ScreenID>
    @Environment(\.flyoverStylesheet) private var stylesheet

    var body: some View {
        ScrollView(.horizontal) {
            HStack(spacing: stylesheet.controlBar.compactSpacing) {
                FlyoverViewModePicker(model: model)
                    .frame(width: stylesheet.controlBar.compactViewModeWidth)
                FlyoverZoomSlider(model: model)
                    .frame(width: stylesheet.controlBar.compactZoomWidth)
                FlyoverViewportMenu(model: model)
                    .labelStyle(.iconOnly)
                FlyoverAppearanceMenu(model: model)
                    .labelStyle(.iconOnly)
                FlyoverResetAllButton(iconOnly: true, reset: resetAll)
            }
        }
        .scrollIndicators(.hidden)
    }

    private func resetAll() {
        model.resetAll(catalog)
    }
}

private struct FlyoverResetAllButton: View {
    let iconOnly: Bool
    let reset: () -> Void

    var body: some View {
        let button = Button("Reset All", systemSymbol: .arrowCounterclockwise, action: reset)
        if iconOnly {
            button.labelStyle(.iconOnly)
        } else {
            button
        }
    }
}

/// A linear alternative to the spatial Flyover canvas.
private struct FlyoverListView<ScreenID: Hashable>: View {
    let catalog: FlyoverCatalog<ScreenID>
    let model: FlyoverModel<ScreenID>
    @Environment(\.flyoverStylesheet) private var stylesheet

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: stylesheet.list.groupSpacing) {
                ForEach(catalog.groups, id: \.id) { group in
                    FlyoverListSection(group: group, catalog: catalog, model: model)
                }
            }
            .padding(stylesheet.list.contentPadding)
        }
    }
}

private struct FlyoverListSection<ScreenID: Hashable>: View {
    let group: FlyoverGroup<ScreenID>
    let catalog: FlyoverCatalog<ScreenID>
    let model: FlyoverModel<ScreenID>
    @Environment(\.flyoverStylesheet) private var stylesheet

    var body: some View {
        Section {
            ForEach(group.screens, id: \.id) { screen in
                FlyoverScreenFrame(
                    screen: screen,
                    catalog: catalog,
                    model: model,
                )
                .frame(maxWidth: .infinity)
            }
        } header: {
            Text(group.title)
                .font(stylesheet.list.groupTitleFont)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

#if DEBUG
    #Preview {
        FlyoverView(catalog: FlyoverPreview.catalog)
    }
#endif

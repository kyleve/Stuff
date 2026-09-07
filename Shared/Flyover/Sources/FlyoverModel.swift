import Observation
import SnapshotKit
import SwiftUI

/// Main-actor session state for a Flyover browser.
@MainActor
@Observable
final class FlyoverModel<ScreenID: Hashable> {
    var viewMode = FlyoverViewMode.canvas
    var zoom = 0.45
    var device = FlyoverDevice.phone
    var orientation = FlyoverOrientation.portrait
    var appearance = FlyoverAppearance.system
    var dynamicType = FlyoverDynamicType.large
    var contrast = ColorSchemeContrast.standard
    var layoutDirection = LayoutDirection.leftToRight
    var legibilityWeight = LegibilityWeight.regular
    var focusedSelection: FlyoverSelection<ScreenID>?
    private(set) var previewedScreenID: ScreenID?

    let contentLoadCoordinator = FlyoverContentLoadCoordinator()
    let previewReadiness = FlyoverPreviewReadiness<ScreenID>()
    private let frameStates: [ScreenID: FlyoverFrameState]
    private(set) var hasAppliedInitialCanvasZoom = false

    init(catalog: FlyoverCatalog<ScreenID>) {
        frameStates = catalog.screens.reduce(into: [:]) { states, screen in
            guard states[screen.id] == nil else {
                return
            }
            states[screen.id] = FlyoverFrameState(variantID: screen.variants[0].id)
        }
    }

    var viewportSize: CGSize {
        let portrait = device.portraitSize
        switch orientation {
            case .portrait:
                return portrait
            case .landscape:
                return CGSize(width: portrait.height, height: portrait.width)
        }
    }

    func state(for screen: FlyoverScreen<ScreenID>) -> FlyoverFrameState {
        guard let state = frameStates[screen.id] else {
            preconditionFailure("Every Flyover screen must receive frame state.")
        }
        return state
    }

    func variant(for screen: FlyoverScreen<ScreenID>) -> FlyoverVariant {
        let selectedID = state(for: screen).variantID
        return screen.variants.first { $0.id == selectedID } ?? screen.variants[0]
    }

    func previewLoadKey(for screen: FlyoverScreen<ScreenID>) -> FlyoverPreviewReadiness<ScreenID>
        .LoadKey
    {
        let state = state(for: screen)
        return FlyoverPreviewReadiness<ScreenID>.LoadKey(
            screenID: screen.id,
            variantID: variant(for: screen).id,
            generation: state.generation,
        )
    }

    func waitUntilVisiblePreviewsAreLoaded() async {
        await previewReadiness.waitUntilReady()
    }

    func focus(_ screen: FlyoverScreen<ScreenID>) {
        focusedSelection = FlyoverSelection(id: screen.id)
    }

    func preview(_ screen: FlyoverScreen<ScreenID>) {
        previewedScreenID = screen.id
    }

    func pausePreview() {
        previewedScreenID = nil
    }

    func applyInitialCanvasZoom(_ zoom: Double) {
        guard hasAppliedInitialCanvasZoom == false else {
            return
        }
        hasAppliedInitialCanvasZoom = true
        self.zoom = zoom
    }

    func reset(_ screen: FlyoverScreen<ScreenID>) {
        screen.resetAction()
        let state = state(for: screen)
        state.variantID = screen.variants[0].id
        state.generation += 1
    }

    func resetAll(_ catalog: FlyoverCatalog<ScreenID>) {
        for screen in catalog.screens {
            reset(screen)
        }
    }

    func configuration(
        for screen: FlyoverScreen<ScreenID>,
        systemColorScheme: ColorScheme,
    ) -> SnapshotConfiguration {
        let colorScheme = switch appearance {
            case .system: systemColorScheme
            case .light: ColorScheme.light
            case .dark: ColorScheme.dark
        }
        return SnapshotConfiguration(
            colorScheme: colorScheme,
            dynamicType: dynamicType.value,
            contrast: contrast,
            layoutDirection: layoutDirection,
            legibilityWeight: legibilityWeight,
            device: SnapshotConfiguration.Frame(
                name: "Flyover",
                size: .fixed(size(for: screen)),
            ),
        )
    }

    func size(for screen: FlyoverScreen<ScreenID>) -> CGSize {
        switch screen.viewport {
            case .device:
                viewportSize
            case let .fixed(size):
                size
        }
    }
}

import SwiftUI

/// One inspectable screen and its local states and controls.
@MainActor
public struct FlyoverScreen<ScreenID: Hashable> {
    public let id: ScreenID
    public let title: String
    public let viewport: FlyoverViewport
    public let position: FlyoverPosition?
    public let navigationContainer: FlyoverNavigationContainer
    public let variants: [FlyoverVariant]
    public let controls: [FlyoverControl]
    let customControls: AnyView?
    let resetAction: @MainActor () -> Void

    public init(
        id: ScreenID,
        title: String,
        viewport: FlyoverViewport = .device,
        position: FlyoverPosition? = nil,
        navigationContainer: FlyoverNavigationContainer = .stack,
        variants: [FlyoverVariant],
        controls: [FlyoverControl] = [],
        reset: @escaping @MainActor () -> Void = {},
        @ViewBuilder customControls: () -> some View,
    ) {
        precondition(variants.isEmpty == false, "A Flyover screen must have a variant.")
        self.id = id
        self.title = title
        self.viewport = viewport
        self.position = position
        self.navigationContainer = navigationContainer
        self.variants = variants
        self.controls = controls
        self.customControls = AnyView(customControls())
        resetAction = reset
    }

    public init(
        id: ScreenID,
        title: String,
        viewport: FlyoverViewport = .device,
        position: FlyoverPosition? = nil,
        navigationContainer: FlyoverNavigationContainer = .stack,
        variants: [FlyoverVariant],
        controls: [FlyoverControl] = [],
        reset: @escaping @MainActor () -> Void = {},
    ) {
        precondition(variants.isEmpty == false, "A Flyover screen must have a variant.")
        self.id = id
        self.title = title
        self.viewport = viewport
        self.position = position
        self.navigationContainer = navigationContainer
        self.variants = variants
        self.controls = controls
        customControls = nil
        resetAction = reset
    }
}

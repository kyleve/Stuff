import UIKit

/// An atomic reading of one window and its owning screen, without assumptions about physical
/// panels.
struct DisplayReading: Equatable {
    struct Screen: Equatable {
        let bounds: CGRect
        let nativeBounds: CGRect
        let scale: CGFloat
        let nativeScale: CGFloat
        let modePixels: CGSize?
        let maximumFramesPerSecond: Int
    }

    struct Window: Equatable {
        let sceneBounds: CGRect
        let bounds: CGRect
        let safeArea: UIEdgeInsets
        let orientation: UIInterfaceOrientation
    }

    struct Field {
        let label: String
        let value: String
    }

    let screen: Screen
    let window: Window

    @MainActor
    static func capture(window: UIWindow) -> DisplayReading? {
        guard let scene = window.windowScene else { return nil }
        let screen = scene.screen
        return DisplayReading(
            screen: Screen(
                bounds: screen.bounds,
                nativeBounds: screen.nativeBounds,
                scale: screen.scale,
                nativeScale: screen.nativeScale,
                modePixels: screen.currentMode?.size,
                maximumFramesPerSecond: screen.maximumFramesPerSecond,
            ),
            window: Window(
                sceneBounds: scene.effectiveGeometry.coordinateSpace.bounds,
                bounds: window.bounds,
                safeArea: window.safeAreaInsets,
                orientation: scene.effectiveGeometry.interfaceOrientation,
            ),
        )
    }

    var fields: [Field] {
        [
            Field(label: "Screen bounds · points", value: Self.dimensions(screen.bounds.size)),
            Field(
                label: "Native bounds · pixels",
                value: Self.dimensions(screen.nativeBounds.size),
            ),
            Field(label: "Rendering scale · scale", value: "\(Self.number(screen.scale))×"),
            Field(
                label: "Native scale · nativeScale",
                value: "\(Self.number(screen.nativeScale))×",
            ),
            Field(
                label: "Current mode · pixels",
                value: screen.modePixels.map(Self.dimensions) ?? "Unavailable",
            ),
            Field(label: "Scene bounds · points", value: Self.dimensions(window.sceneBounds.size)),
            Field(label: "Window bounds · points", value: Self.dimensions(window.bounds.size)),
            Field(label: "Window safe area · points", value: safeAreaDescription),
            Field(label: "Interface orientation", value: orientationDescription),
            Field(label: "Maximum refresh rate", value: "\(screen.maximumFramesPerSecond) Hz"),
        ]
    }

    var report: String {
        fields.map { "\($0.label): \($0.value)" }.joined(separator: "\n")
    }

    static func dimensions(_ size: CGSize) -> String {
        "\(number(size.width)) × \(number(size.height))"
    }

    static func number(_ value: CGFloat) -> String {
        Double(value).formatted(.number.grouping(.never).precision(.fractionLength(0 ... 3)))
    }

    private var safeAreaDescription: String {
        let insets = window.safeArea
        return "Top \(Self.number(insets.top)), bottom \(Self.number(insets.bottom)), left \(Self.number(insets.left)), right \(Self.number(insets.right))"
    }

    private var orientationDescription: String {
        switch window.orientation {
            case .unknown: "Unknown"
            case .portrait: "Portrait"
            case .portraitUpsideDown: "Portrait upside down"
            case .landscapeLeft: "Landscape left"
            case .landscapeRight: "Landscape right"
            @unknown default: "Unknown system orientation"
        }
    }
}

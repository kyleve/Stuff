import BroadwayUI
import SwiftUI

/// One presentation shared by a viewer and its drill-ins, or loaded for a standalone tool.
struct PeriscopeToolPresentation: Equatable {
    let density: PeriscopeStylesheet.Density

    enum Source {
        case density(PeriscopeStylesheet.Density)
        case inheritedOrSaved(UserDefaults)
    }
}

extension View {
    /// Seeds tool styling and resolves density at the chosen presentation boundary.
    func periscopeBroadwayRoot(_ source: PeriscopeToolPresentation.Source) -> some View {
        modifier(PeriscopeToolPresentationModifier(source: source))
    }
}

extension EnvironmentValues {
    @Entry var periscopeToolPresentation: PeriscopeToolPresentation?

    /// The rootless fallback preserves component previews without a tool host.
    var logRowDensity: PeriscopeStylesheet.Density {
        periscopeToolPresentation?.density ?? .comfortable
    }
}

private struct PeriscopeToolPresentationModifier: ViewModifier {
    let source: PeriscopeToolPresentation.Source
    @Environment(\.periscopeToolPresentation) private var inherited

    func body(content: Content) -> some View {
        let presentation: PeriscopeToolPresentation = switch source {
            case let .density(density):
                PeriscopeToolPresentation(density: density)
            case let .inheritedOrSaved(defaults):
                inherited ?? PeriscopeToolPresentation(density: .load(from: defaults))
        }
        content
            .environment(\.periscopeToolPresentation, presentation)
            .broadwayRoot(themes: PeriscopeThemes.current)
    }
}

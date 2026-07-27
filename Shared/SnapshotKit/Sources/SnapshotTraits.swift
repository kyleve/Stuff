import SwiftUI
import UIKit

extension View {
    /// Applies a ``SnapshotConfiguration``'s appearance traits to this view so a
    /// preview renders the way its snapshot will be captured.
    ///
    /// Color scheme, Dynamic Type, layout direction, and legibility weight go
    /// through the SwiftUI environment; increased contrast has no SwiftUI setter,
    /// so that variant is hosted once through a UIKit trait override (which the
    /// hosting controller bridges back into the content's `colorSchemeContrast`).
    @ViewBuilder
    public func snapshotTraits(_ configuration: SnapshotConfiguration) -> some View {
        let base = environment(\.colorScheme, configuration.colorScheme)
            .dynamicTypeSize(configuration.dynamicType)
            .environment(\.layoutDirection, configuration.layoutDirection)
            .environment(\.legibilityWeight, configuration.legibilityWeight)
        if configuration.contrast == .increased {
            ContrastOverrideHost { base }
        } else {
            base
        }
    }
}

/// Hosts content with an increased-contrast trait override — the only appearance
/// axis SwiftUI can't set directly. Sized to its content so it lays out inline in
/// the preview cutsheet.
private struct ContrastOverrideHost<Content: View>: UIViewControllerRepresentable {
    @ViewBuilder var content: () -> Content

    func makeUIViewController(context _: Context) -> UIHostingController<Content> {
        let host = UIHostingController(rootView: content())
        host.view.backgroundColor = .clear
        host.sizingOptions = [.intrinsicContentSize]
        host.traitOverrides.accessibilityContrast = .high
        return host
    }

    func updateUIViewController(_ host: UIHostingController<Content>, context _: Context) {
        host.rootView = content()
        host.traitOverrides.accessibilityContrast = .high
    }
}

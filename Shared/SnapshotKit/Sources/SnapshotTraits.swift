import SwiftUI
import UIKit

extension View {
    /// Applies a ``SnapshotConfiguration``'s appearance traits to this view so a
    /// preview renders the way its snapshot will be captured.
    ///
    /// Color scheme, Dynamic Type, layout direction, and legibility weight go
    /// through the SwiftUI environment. A UIKit host supplies increased contrast
    /// and explicit layout traits, including interface idiom.
    @ViewBuilder
    public func snapshotTraits(_ configuration: SnapshotConfiguration) -> some View {
        let base = environment(\.colorScheme, configuration.colorScheme)
            .dynamicTypeSize(configuration.dynamicType)
            .environment(\.layoutDirection, configuration.layoutDirection)
            .environment(\.legibilityWeight, configuration.legibilityWeight)
            .snapshotLayoutTraits(configuration)
        if configuration.contrast == .increased || configuration.resolvedLayoutTraits != nil {
            SnapshotTraitOverrideHost(configuration: configuration) { base }
        } else {
            base
        }
    }
}

/// Supplies UIKit traits that SwiftUI cannot set directly, including interface
/// idiom. Intrinsic sizing keeps the host inline in the preview cutsheet.
private struct SnapshotTraitOverrideHost<Content: View>: UIViewControllerRepresentable {
    let configuration: SnapshotConfiguration
    @ViewBuilder var content: () -> Content

    func makeUIViewController(context _: Context) -> UIHostingController<Content> {
        let host = UIHostingController(rootView: content())
        host.view.backgroundColor = .clear
        host.sizingOptions = [.intrinsicContentSize]
        configuration.applyTraits(to: host)
        return host
    }

    func updateUIViewController(_ host: UIHostingController<Content>, context _: Context) {
        host.rootView = content()
        configuration.applyTraits(to: host)
    }
}

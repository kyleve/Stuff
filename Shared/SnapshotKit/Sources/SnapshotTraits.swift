import SwiftUI
import UIKit

extension View {
    /// Applies a ``SnapshotConfiguration``'s appearance traits to this view so a
    /// preview renders the way its snapshot will be captured.
    ///
    /// Color scheme, Dynamic Type, layout direction, and legibility weight go
    /// through the SwiftUI environment. Increased contrast and device-adaptive
    /// traits use a UIKit trait override, which the hosting controller bridges
    /// back into the SwiftUI content.
    @ViewBuilder
    public func snapshotTraits(_ configuration: SnapshotConfiguration) -> some View {
        let base = environment(\.colorScheme, configuration.colorScheme)
            .dynamicTypeSize(configuration.dynamicType)
            .environment(\.layoutDirection, configuration.layoutDirection)
            .environment(\.legibilityWeight, configuration.legibilityWeight)
        if configuration.contrast == .increased || configuration.layoutTraits != nil {
            SnapshotTraitOverrideHost(configuration: configuration) { base }
        } else {
            base
        }
    }
}

/// Hosts content with UIKit-only trait overrides. Sized to its content so it
/// lays out inline in the preview cutsheet.
private struct SnapshotTraitOverrideHost<Content: View>: UIViewControllerRepresentable {
    let configuration: SnapshotConfiguration
    @ViewBuilder var content: () -> Content

    func makeUIViewController(context _: Context) -> UIHostingController<Content> {
        let host = UIHostingController(rootView: content())
        host.view.backgroundColor = .clear
        host.sizingOptions = [.intrinsicContentSize]
        applyTraits(to: host)
        return host
    }

    func updateUIViewController(_ host: UIHostingController<Content>, context _: Context) {
        host.rootView = content()
        applyTraits(to: host)
    }

    private func applyTraits(to host: UIHostingController<Content>) {
        applySnapshotTraitOverrides(configuration, to: host)
    }
}

/// Updates the UIKit-only traits and removes device overrides that no longer apply.
@MainActor
func applySnapshotTraitOverrides(
    _ configuration: SnapshotConfiguration,
    to host: UIViewController,
) {
    let traits = configuration.uiTraitCollection
    host.traitOverrides.accessibilityContrast = traits.accessibilityContrast
    if configuration.layoutTraits != nil {
        host.traitOverrides.userInterfaceIdiom = traits.userInterfaceIdiom
        host.traitOverrides.horizontalSizeClass = traits.horizontalSizeClass
        host.traitOverrides.verticalSizeClass = traits.verticalSizeClass
    } else {
        host.traitOverrides.remove(UITraitUserInterfaceIdiom.self)
        host.traitOverrides.remove(UITraitHorizontalSizeClass.self)
        host.traitOverrides.remove(UITraitVerticalSizeClass.self)
    }
}

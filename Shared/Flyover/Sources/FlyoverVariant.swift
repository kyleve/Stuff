@_spi(Capture) import SnapshotKit
import SwiftUI

/// One named content state of a registered screen.
@MainActor
public struct FlyoverVariant {
    public let id: FlyoverVariantID
    public let title: String
    let overviewContent: @MainActor () -> AnyView
    let focusedContent: @MainActor () -> AnyView

    public init(
        id: FlyoverVariantID,
        title: String,
        @ViewBuilder content: @escaping @MainActor () -> some View,
    ) {
        self.id = id
        self.title = title
        overviewContent = { AnyView(content()) }
        focusedContent = { AnyView(content()) }
    }

    public init(
        id: FlyoverVariantID,
        title: String,
        @ViewBuilder overview: @escaping @MainActor () -> some View,
        @ViewBuilder focused: @escaping @MainActor () -> some View,
    ) {
        self.id = id
        self.title = title
        overviewContent = { AnyView(overview()) }
        focusedContent = { AnyView(focused()) }
    }

    /// Adapts each independent subject into its own lazy, interactive variant.
    /// Single-view cases retain their supplied ID; cutsheet IDs append the panel identity.
    public static func snapshots(id: FlyoverVariantID, snapshotCase: SnapshotCase) -> [Self] {
        switch snapshotCase.capture {
            case let .single(content):
                [Self(id: id, title: snapshotCase.name) { content() }]
            case let .cutsheet(collection):
                collection.panels.map { panel in
                    Self(
                        id: FlyoverVariantID("\(id.rawValue)/\(panel.id.rawValue)"),
                        title: "\(snapshotCase.name) — \(panel.label)",
                    ) { panel.content }
                }
        }
    }
}

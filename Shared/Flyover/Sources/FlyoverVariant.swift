import SnapshotKit
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

    /// Adapts existing snapshot content into a Flyover variant.
    public init(id: FlyoverVariantID, snapshotCase: SnapshotCase) {
        self.id = id
        title = snapshotCase.name
        overviewContent = { snapshotCase.content }
        focusedContent = { snapshotCase.content }
    }
}

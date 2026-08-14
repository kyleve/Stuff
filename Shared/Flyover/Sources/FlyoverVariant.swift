import SnapshotKit
import SwiftUI

/// One named content state of a registered screen.
@MainActor
public struct FlyoverVariant {
    public let id: FlyoverVariantID
    public let title: String
    let overviewContent: @MainActor () -> AnyView
    let focusedContent: @MainActor () -> AnyView
    #if DEBUG
        public let exportPolicy: FlyoverExportPolicy
        let exportPolicyResolution: FlyoverExportPolicyResolution
    #endif

    public init(
        id: FlyoverVariantID,
        title: String,
        @ViewBuilder content: @escaping @MainActor () -> some View,
    ) {
        self.id = id
        self.title = title
        overviewContent = { AnyView(content()) }
        focusedContent = { AnyView(content()) }
        #if DEBUG
            exportPolicy = .hosted
            exportPolicyResolution = .policy(.hosted)
        #endif
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
        #if DEBUG
            exportPolicy = .hosted
            exportPolicyResolution = .policy(.hosted)
        #endif
    }

    /// Adapts existing snapshot content into a Flyover variant.
    public init(id: FlyoverVariantID, snapshotCase: SnapshotCase) {
        self.id = id
        title = snapshotCase.name
        overviewContent = { snapshotCase.content }
        focusedContent = { snapshotCase.content }
        #if DEBUG
            exportPolicyResolution = FlyoverExportPolicy.resolution(for: snapshotCase)
            exportPolicy = switch exportPolicyResolution {
                case let .policy(policy): policy
                case .mixed: .hosted
            }
        #endif
    }

    #if DEBUG
        public init(
            id: FlyoverVariantID,
            title: String,
            exportPolicy: FlyoverExportPolicy,
            @ViewBuilder content: @escaping @MainActor () -> some View,
        ) {
            self.id = id
            self.title = title
            overviewContent = { AnyView(content()) }
            focusedContent = { AnyView(content()) }
            self.exportPolicy = exportPolicy
            exportPolicyResolution = .policy(exportPolicy)
        }

        public init(
            id: FlyoverVariantID,
            snapshotCase: SnapshotCase,
            exportPolicy: FlyoverExportPolicy,
        ) {
            self.id = id
            title = snapshotCase.name
            overviewContent = { snapshotCase.content }
            focusedContent = { snapshotCase.content }
            self.exportPolicy = exportPolicy
            exportPolicyResolution = .policy(exportPolicy)
        }
    #endif
}

@_spi(Capture) import SnapshotKit
import SwiftUI

/// One named content state of a registered screen.
@MainActor
public struct FlyoverVariant {
    public let id: FlyoverVariantID
    public let title: String
    let overviewContent: @MainActor () -> AnyView
    let focusedContent: @MainActor () -> AnyView
    #if DEBUG
        public let exportPolicy: FlyoverExportPolicy?
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

    /// Adapts each independent subject into its own lazy, interactive variant.
    /// Single-view cases retain their supplied ID; cutsheet IDs append the panel identity.
    public static func snapshots(id: FlyoverVariantID, snapshotCase: SnapshotCase) -> [Self] {
        switch snapshotCase.capture {
            case let .single(content):
                [Self(id: id, title: snapshotCase.name, snapshotCase: snapshotCase) { content() }]
            case let .cutsheet(collection):
                collection.panels.map { panel in
                    Self(
                        id: FlyoverVariantID("\(id.rawValue)/\(panel.id.rawValue)"),
                        title: "\(snapshotCase.name) — \(panel.label)",
                        snapshotCase: snapshotCase,
                    ) { panel.content }
                }
        }
    }

    private init(
        id: FlyoverVariantID,
        title: String,
        snapshotCase: SnapshotCase,
        content: @escaping @MainActor () -> AnyView,
    ) {
        self.id = id
        self.title = title
        overviewContent = content
        focusedContent = content
        #if DEBUG
            exportPolicyResolution = FlyoverExportPolicy.resolution(for: snapshotCase)
            exportPolicy = switch exportPolicyResolution {
                case let .policy(policy): policy
                case .mixed: nil
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

        public static func snapshots(
            id: FlyoverVariantID,
            snapshotCase: SnapshotCase,
            exportPolicy: FlyoverExportPolicy,
        ) -> [Self] {
            snapshots(id: id, snapshotCase: snapshotCase).map { variant in
                Self(id: variant.id, title: variant.title, exportPolicy: exportPolicy) {
                    variant.overviewContent()
                }
            }
        }
    #endif
}

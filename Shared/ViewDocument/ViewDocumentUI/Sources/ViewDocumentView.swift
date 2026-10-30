import SwiftUI
import ViewDocumentCore

/// Renders validated read-only content. Host policy controls motion and decorative use.
public struct ViewDocumentView: View {
    private let document: ValidatedViewDocument
    private let assets: ViewDocumentAssets
    private let appearance: ViewDocumentAppearance
    private let policy: Policy

    public struct Policy: Equatable, Sendable {
        public var purpose: Purpose
        public var isActive: Bool
        public var motionIsStatic: Bool

        public init(purpose: Purpose, isActive: Bool, motionIsStatic: Bool) {
            self.purpose = purpose
            self.isActive = isActive
            self.motionIsStatic = motionIsStatic
        }

        public enum Purpose: Sendable {
            case content, decoration
        }
    }

    public init(
        document: ValidatedViewDocument,
        assets: ViewDocumentAssets,
        appearance: ViewDocumentAppearance,
        policy: Policy,
    ) throws {
        let prepared = try PreparedViewDocument(document: document, assets: assets)
        self.init(prepared: prepared, appearance: appearance, policy: policy)
    }

    public init(
        prepared: PreparedViewDocument,
        appearance: ViewDocumentAppearance,
        policy: Policy,
    ) {
        let document = prepared.document
        let assets = prepared.assets
        self.document = document
        self.assets = assets
        self.appearance = appearance
        self.policy = policy
    }

    public enum ResourceError: Error {
        case mismatchedAssets
    }

    public var body: some View {
        ViewDocumentNodeView(
            node: document.document.root,
            assets: assets,
            appearance: appearance,
            policy: policy,
        )
        .id(document.document)
        .accessibilityHidden(policy.purpose == .decoration)
        .allowsHitTesting(false)
    }
}

#if DEBUG
    #Preview("Read-only document") { ViewDocumentPreview.make() }

    @MainActor
    private enum ViewDocumentPreview {
        static func make() -> ViewDocumentView {
            do {
                let assets = ViewDocumentAssets(images: [:], symbols: [:])
                let document = try ValidatedViewDocument(
                    document: .init(schemaVersion: 1, root: .init(
                        id: .init(rawValue: "greeting"),
                        content: .text("Hello from ViewDocument"),
                        modifiers: [
                            .font(.init(size: .semantic(.title), weight: .bold, design: .rounded)),
                            .padding(.points(24)),
                        ],
                        animation: nil,
                        accessibility: .automatic,
                    )),
                    resources: assets.resources,
                    limits: .standard,
                )
                return try ViewDocumentView(
                    document: document,
                    assets: assets,
                    appearance: .init(background: .white, dimensionScales: [:]),
                    policy: .init(purpose: .content, isActive: true, motionIsStatic: true),
                )
            } catch {
                preconditionFailure("Invalid built-in preview: \(error)")
            }
        }
    }
#endif

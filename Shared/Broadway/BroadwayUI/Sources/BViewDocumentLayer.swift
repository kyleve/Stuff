import BroadwayCore
import SwiftUI
import ViewDocumentCore
import ViewDocumentUI

/// A decoration resolves through the nearest Broadway context and stays inside its host bounds.
public struct BViewDocumentLayer: View {
    let document: PreparedViewDocument
    let isActive: Bool
    let motionIsStatic: Bool
    @Environment(\.bViewDocumentStylesheet) private var sheet

    public init(document: PreparedViewDocument, isActive: Bool, motionIsStatic: Bool) {
        self.document = document
        self.isActive = isActive
        self.motionIsStatic = motionIsStatic
    }

    public var body: some View {
        if sheet.showsDecoration {
            ViewDocumentView(
                prepared: document,
                appearance: sheet.appearance,
                policy: .init(
                    purpose: .decoration,
                    isActive: isActive,
                    motionIsStatic: motionIsStatic || sheet.motionIsStatic,
                ),
            )
        }
    }
}

extension View {
    /// Adds a bounded background without changing the host's layout or hit area.
    public func bViewDocumentBackground(
        _ document: PreparedViewDocument,
        isActive: Bool,
        motionIsStatic: Bool,
    ) -> some View {
        background {
            GeometryReader { geometry in
                BViewDocumentLayer(
                    document: document,
                    isActive: isActive,
                    motionIsStatic: motionIsStatic,
                )
                .frame(width: geometry.size.width, height: geometry.size.height)
                .clipped()
            }
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        }
    }

    /// Adds a bounded overlay without changing the host's layout or hit area.
    public func bViewDocumentOverlay(
        _ document: PreparedViewDocument,
        isActive: Bool,
        motionIsStatic: Bool,
    ) -> some View {
        overlay {
            GeometryReader { geometry in
                BViewDocumentLayer(
                    document: document,
                    isActive: isActive,
                    motionIsStatic: motionIsStatic,
                )
                .frame(width: geometry.size.width, height: geometry.size.height)
                .clipped()
            }
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        }
    }
}

extension EnvironmentValues {
    public var bViewDocumentStylesheet: BViewDocumentStylesheet {
        bContext.stylesheet(BViewDocumentStylesheet.self, fallback: .default)
    }
}

#if DEBUG
    #Preview("Broadway document decoration") { BViewDocumentPreview.make() }

    @MainActor
    private enum BViewDocumentPreview {
        static func make() -> some View {
            do {
                let validated = try ValidatedViewDocument(
                    document: .init(schemaVersion: 1, root: .init(
                        id: .init(rawValue: "artwork"),
                        content: .shape(.circle),
                        modifiers: [
                            .foreground(.color(.semantic(.accent))),
                            .frame(
                                width: .scaled(points: 40, relativeTo: .body),
                                height: .scaled(points: 40, relativeTo: .body),
                                alignment: .center,
                            ),
                        ],
                        animation: nil,
                        accessibility: .hidden,
                    )),
                    resources: .init(images: [], symbols: []),
                    limits: .standard,
                )
                let prepared = try PreparedViewDocument(
                    document: validated,
                    assets: .init(images: [:], symbols: [:]),
                )
                return Color.clear.frame(width: 200, height: 120)
                    .bViewDocumentBackground(prepared, isActive: true, motionIsStatic: true)
                    .broadwayRoot()
            } catch {
                preconditionFailure("Invalid Broadway preview: \(error)")
            }
        }
    }
#endif

import SnapshotKit
import SnapshotKitTesting
import SwiftUI
import Testing
import ViewDocumentCore
import ViewDocumentUI

@MainActor
struct ViewDocumentViewSnapshotTests {
    @Test func standaloneContent() async throws {
        let root = ViewDocument.Node(
            id: .init(rawValue: "root"),
            content: .group(axis: .vertical, alignment: .center, spacing: 20, children: [
                .init(
                    id: .init(rawValue: "title"),
                    content: .text("A document rendered with SwiftUI"),
                    modifiers: [.font(.init(
                        size: .semantic(.title2),
                        weight: .bold,
                        design: .rounded,
                    ))],
                    animation: nil,
                    accessibility: .automatic,
                ),
                .init(
                    id: .init(rawValue: "art"),
                    content: .shape(.roundedRectangle(radius: 18)),
                    modifiers: [
                        .foreground(.linearGradient(
                            stops: [.init(
                                color: .rgba(red: 1, green: 0.4, blue: 0.1, alpha: 1),
                                location: 0,
                            ), .init(
                                color: .rgba(red: 0.6, green: 0.1, blue: 0.3, alpha: 1),
                                location: 1,
                            )],
                            start: .init(x: 0, y: 0),
                            end: .init(x: 1, y: 1),
                        )),
                        .frame(width: .points(160), height: .points(100), alignment: .center),
                        .rotation(degrees: 8),
                    ],
                    animation: nil,
                    accessibility: .label("Orange and red artwork"),
                ),
                .init(
                    id: .init(rawValue: "caption"),
                    content: .text("Finite layouts. Ordered modifiers. Accessible content."),
                    modifiers: [.font(.init(
                        size: .semantic(.body),
                        weight: .regular,
                        design: .standard,
                    ))],
                    animation: nil,
                    accessibility: .automatic,
                ),
            ]),
            modifiers: [.padding(.points(24))],
            animation: nil,
            accessibility: .contain,
        )
        let assets = ViewDocumentAssets(images: [:], symbols: [:])
        let document = try ValidatedViewDocument(
            document: .init(schemaVersion: 1, root: root),
            resources: assets.resources,
            limits: .standard,
        )
        let view = try ViewDocumentView(
            document: document,
            assets: assets,
            appearance: .init(background: .white, dimensionScales: [:]),
            policy: .init(purpose: .content, isActive: true, motionIsStatic: true),
        )
        await assertSnapshots(
            of: view.padding().frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(uiColor: .systemBackground)),
            named: "ReadOnlyContent",
            configurations: SnapshotConfiguration.combinations(
                devices: [.iPhone],
                colorSchemes: [.light, .dark],
                snapshotTypes: [.standard, .accessibility],
            ),
        )
    }
}

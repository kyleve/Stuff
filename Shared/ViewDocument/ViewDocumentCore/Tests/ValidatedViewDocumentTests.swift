import Foundation
import Testing
import ViewDocumentCore

struct ValidatedViewDocumentTests {
    @Test func retainsOnlyReferencedResources() throws {
        let used = ViewAssetID(rawValue: "used")
        let unused = ViewAssetID(rawValue: "unused")
        let result = try ValidatedViewDocument(
            document: .init(schemaVersion: 1, root: documentNode("image", content: .image(used))),
            resources: .init(images: [used, unused], symbols: []),
            limits: .standard,
        )
        #expect(result.resources.images == [used])
    }

    @Test func rejectsDuplicateIdentities() throws {
        let child = documentNode("same", content: .text("One"))
        let root = documentNode(
            "root",
            content: .group(
                axis: .vertical,
                alignment: .leading,
                spacing: 2,
                children: [child, child],
            ),
        )
        let error = #expect(throws: ViewDocumentValidationError.self) {
            try ValidatedViewDocument(
                document: .init(schemaVersion: 1, root: root),
                resources: noDocumentResources,
                limits: .standard,
            )
        }
        #expect(error?.path.contains("children[1]") == true)
    }

    @Test func rejectsUnavailableAssets() {
        #expect(throws: ViewDocumentValidationError.self) {
            try ValidatedViewDocument(
                document: .init(schemaVersion: 1, root: documentNode(
                    "image",
                    content: .image(.init(rawValue: "pumpkin")),
                )),
                resources: noDocumentResources,
                limits: .standard,
            )
        }
    }

    @Test(arguments: [Double.nan, .infinity, -0.1, 1.1])
    func rejectsInvalidOpacity(_ opacity: Double) {
        #expect(throws: ViewDocumentValidationError.self) {
            try ValidatedViewDocument(
                document: .init(schemaVersion: 1, root: documentNode(
                    "shape",
                    content: .shape(.circle),
                    modifiers: [.opacity(opacity)],
                )),
                resources: noDocumentResources,
                limits: .standard,
            )
        }
    }

    @Test func enforcesDepthAndNodeLimits() {
        let root = documentNode(
            "root",
            content: .group(
                axis: .overlay,
                alignment: .center,
                spacing: 0,
                children: [documentNode("child", content: .text("Hello"))],
            ),
        )
        for limits in [
            ViewDocumentLimits(bytes: 10000, depth: 1, nodes: 10, animatedNodes: 0),
            .init(bytes: 10000, depth: 10, nodes: 1, animatedNodes: 0),
        ] {
            #expect(throws: ViewDocumentValidationError.self) {
                try ValidatedViewDocument(
                    document: .init(schemaVersion: 1, root: root),
                    resources: noDocumentResources,
                    limits: limits,
                )
            }
        }
    }

    @Test func rejectsVersionAndOversizedInput() {
        #expect(throws: ViewDocumentValidationError.self) {
            try ValidatedViewDocument(
                document: .init(schemaVersion: 2, root: documentNode(
                    "root",
                    content: .text("Hello"),
                )),
                resources: noDocumentResources,
                limits: .standard,
            )
        }
        #expect(throws: ViewDocumentValidationError.self) {
            try ValidatedViewDocument.decode(
                Data(repeating: 32, count: 1024),
                resources: noDocumentResources,
                limits: .init(bytes: 100, depth: 16, nodes: 256, animatedNodes: 32),
            )
        }
    }

    @Test func changedContentHasDifferentIdentity() throws {
        let first = try ValidatedViewDocument(
            document: .init(schemaVersion: 1, root: documentNode("same", content: .text("First"))),
            resources: noDocumentResources,
            limits: .standard,
        )
        let second = try ValidatedViewDocument(
            document: .init(schemaVersion: 1, root: documentNode("same", content: .text("Second"))),
            resources: noDocumentResources,
            limits: .standard,
        )
        #expect(first != second)
        #expect(Set([first, second]).count == 2)
    }
}

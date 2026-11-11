import Foundation
import Testing
import ViewDocumentCore

struct ViewDocumentTests {
    @Test func preservesOrderedModifiersAndTypedIdentity() throws {
        let document = ViewDocument(
            schemaVersion: 1,
            root: documentNode("label", content: .text("Hello"), modifiers: [
                .padding(.points(8)),
                .opacity(0.5),
                .rotation(degrees: 12),
            ]),
        )
        let data = try JSONEncoder().encode(document)
        let decoded = try JSONDecoder().decode(ViewDocument.self, from: data)
        #expect(decoded == document)
        #expect(decoded.root.modifiers.count == 3)
    }

    @Test func literalJSONIsAnIndependentInput() throws {
        let json = Data(
            #"{"schemaVersion":1,"root":{"id":"greeting","content":{"text":{"_0":"Hello"}},"modifiers":[],"accessibility":{"automatic":{}}}}"#
                .utf8,
        )
        let result = try ValidatedViewDocument.decode(
            json,
            resources: noDocumentResources,
            limits: .standard,
        )
        #expect(result.document.root.content == .text("Hello"))
    }
}

import Foundation
import PortholeCore
@testable import PortholeUI
import Testing

struct PortholeEvidenceReferenceTests {
    @Test func recognizesNestedTypedEvidenceWithoutLosingScopeOrHash() throws {
        let scope = PortholeScopeToken(id: .init(rawValue: "app"), generation: UUID())
        let object = PortholeObjectReference(id: UUID(), scope: scope, typeName: "Example.Detector")
        let source = PortholeSourceFile(path: "Detector.swift", content: "one\ntwo")
        let value = try PortholeValue.object([
            "result": .object(["$reference": .encoding(object)]),
            "source": .object([
                "path": .string(source.path),
                "firstLine": .integer(2),
                "sha256": .string(source.sha256),
                "scope": .encoding(scope),
                "text": .string("two"),
            ]),
        ])
        let scan = PortholeEvidenceReference.scan(value)
        #expect(scan.issues.isEmpty)
        #expect(scan.links.map(\.reference) == [
            .object(object),
            .source(.init(scope: scope, path: source.path, line: 2, sha256: source.sha256)),
        ])
        #expect(scan.links[0].id != scan.links[1].id)
    }

    @Test func refusesMalformedReferencesAndDoesNotGuessFromText() {
        let scan = PortholeEvidenceReference
            .scan(.object(["$reference": .string("not a reference")]))
        #expect(scan.links.isEmpty)
        #expect(scan.issues.count == 1)
        #expect(PortholeEvidenceReference.scan(.object([
            "path": .string("Detector.swift"),
            "line": .integer(2),
        ])).links.isEmpty)
        #expect(PortholeEvidenceReference.scan(.string(UUID().uuidString)).links.isEmpty)
    }

    @Test func validatesSavedSourceAndBoundsTraversal() {
        let corrupt = PortholeValue.object([
            "path": .string("x.swift"),
            "content": .string("changed"),
            "sha256": .string(String(repeating: "0", count: 64)),
        ])
        #expect(PortholeEvidenceReference.scan(corrupt).issues.count == 1)
        let many = PortholeEvidenceReference.scan(.array(Array(repeating: .null, count: 10000)))
        #expect(many.truncated)
        #expect(many.links.isEmpty)
    }
}

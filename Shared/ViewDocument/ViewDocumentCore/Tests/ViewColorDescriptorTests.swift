import Foundation
import Testing
import ViewDocumentCore

struct ViewColorDescriptorTests {
    @Test func semanticCompositionsRoundTrip() throws {
        let color = ViewColorDescriptor.mix(
            .semantic(.primary),
            .opacity(.semantic(.accent), 0.7),
            fraction: 0.25,
        )
        #expect(try JSONDecoder().decode(
            ViewColorDescriptor.self,
            from: JSONEncoder().encode(color),
        ) == color)
        _ = try validate(color)
    }

    @Test func rejectsUnboundedCompositionsAndInvalidFractions() throws {
        var deep = ViewColorDescriptor.semantic(.primary)
        for _ in 0 ..< 9 {
            deep = .opacity(deep, 0.5)
        }
        for color in [
            deep,
            .opacity(.semantic(.primary), .infinity),
            .mix(.semantic(.primary), .semantic(.accent), fraction: -0.1),
        ] {
            #expect(throws: ViewDocumentValidationError.self) { try validate(color) }
        }
    }

    private func validate(_ color: ViewColorDescriptor) throws -> ValidatedViewDocument {
        try .init(
            document: .init(schemaVersion: 1, root: documentNode(
                "color",
                content: .shape(.rectangle),
                modifiers: [.foreground(.color(color))],
            )),
            resources: .init(images: [], symbols: []),
            limits: .standard,
        )
    }
}

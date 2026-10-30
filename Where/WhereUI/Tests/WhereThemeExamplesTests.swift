import Foundation
import Testing
@testable import WhereUI

@MainActor
struct WhereThemeExamplesTests {
    @Test func bundledExamplesDecodePrepareAndRoundTrip() throws {
        for example in WhereThemeExamples.allCases {
            let prepared = try example.prepare()
            let document = prepared.validated.document
            #expect(try JSONDecoder().decode(
                WhereThemeDocument.self,
                from: JSONEncoder().encode(document),
            ) == document)
            #expect(!prepared.layers.isEmpty)
        }
    }
}

import Foundation
@testable import TestImpactIndex
import Testing

struct IndexCollectorTests {
    @Test func compiledReferencesIncludeTransitiveHelpersAndImplicitMembers() throws {
        let fixture = try CompilerFixture()
        defer { fixture.remove() }
        try fixture.write("Helper.swift", "func helper() -> Int { 1 }")
        try fixture.write("Renderable.swift", """
        protocol Renderable { var body: Int { get } }
        func render<T: Renderable>(_ value: T) -> Int { value.body }
        """)
        try fixture.write("Card.swift", "struct Card: Renderable {}")
        try fixture.write("CardBody.swift", "extension Card { var body: Int { helper() } }")
        try fixture.write("Other.swift", "struct Other: Renderable { var body: Int { 2 } }")
        try fixture.write("CardTests.swift", "func cardTest() -> Bool { render(Card()) == 1 }")
        try fixture.write("OtherTests.swift", "func otherTest() -> Bool { render(Other()) == 2 }")
        try fixture.write("Main.swift", """
        import Darwin
        @main struct Main {
            static func main() {
                let card = cardTest()
                let other = otherTest()
                print("CardTests=\\(card),OtherTests=\\(other)")
                exit(card && other ? 0 : 1)
            }
        }
        """)
        try fixture.build()
        #expect(try fixture.run().status == 0)
        let before = try fixture.collect()
        let card = try #require(before.first { $0.path == "CardTests.swift" })
        let view = try #require(before.first { $0.path == "CardBody.swift" })
        let other = try #require(before.first { $0.path == "OtherTests.swift" })
        #expect(card.dependencies.contains("Card.swift"))
        #expect(card.dependencies.contains("CardBody.swift"))
        #expect(view.dependencies.contains("Helper.swift"))
        #expect(other.dependencies.contains("Card.swift") == false)
        #expect(before.filter { $0.indexed == false }.isEmpty)

        // The oracle runs both tests and observes the deliberately introduced regression.
        try fixture.write("Helper.swift", "func helper() -> Int { 99 }")
        let stale = try fixture.collect()
        #expect(stale.first { $0.path == "Helper.swift" }?.indexed == false)
        try fixture.build()
        let result = try fixture.run()
        #expect(result.status == 1)
        #expect(result.output.contains("CardTests=false,OtherTests=true"))
        let after = try fixture.collect()
        #expect(after.first { $0.path == "Helper.swift" }?.definitions == before
            .first { $0.path == "Helper.swift" }?.definitions)
        #expect(after.filter { $0.indexed == false }.isEmpty)
    }
}

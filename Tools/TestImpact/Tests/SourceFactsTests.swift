@testable import TestImpactIndex
import Testing

struct SourceFactsTests {
    @Test func findsCaptureWithoutTreatingCommentsAsDependencies() {
        let facts = SourceFacts.read("""
        // assertSnapshots(of: Wrong.self)
        struct CardTests {
            @Test func snapshot() async {
                await assertSnapshots(of: Card.self)
            }
        }
        """)
        #expect(facts.captures == ["Card"])
        #expect(facts.declarations == ["CardTests"])
        #expect(facts.risks.isEmpty)
    }

    @Test(arguments: [
        "NotificationCenter.default",
        "NSClassFromString(\"Card\")",
        "Mirror(reflecting: item)"
    ])
    func flagsDynamicDependencies(_ expression: String) {
        #expect(SourceFacts.read("let value = \(expression)").risks.contains("dynamic-behavior"))
    }

    @Test func detectsConditionalsAndIncompleteSyntax() {
        #expect(SourceFacts.read("#if CUSTOM\nlet x = 1\n#endif").risks
            .contains("conditional-compilation"))
        #expect(SourceFacts.read("#if DEBUG\n#Preview { Card() }\n#endif").risks.isEmpty)
        #expect(SourceFacts.read("struct Broken {").risks.contains("syntax-errors"))
    }

    @Test func distinguishesBodyChangesFromDeclarationChanges() {
        let original = SourceFacts.read("struct Card { func value() -> Int { 1 } }")
        let changedBody = SourceFacts.read("struct Card { func value() -> Int { 99 } }")
        let changedConformance = SourceFacts
            .read("struct Card: Sendable { func value() -> Int { 1 } }")
        let changedSignature = SourceFacts.read("struct Card { func value() -> Double { 1 } }")
        #expect(original.shape == changedBody.shape)
        #expect(original.shape != changedConformance.shape)
        #expect(original.shape != changedSignature.shape)
    }
}

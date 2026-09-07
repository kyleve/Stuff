import BumperBowlingCore
import BumperBowlingTestSupport
import Testing

struct RepositoryProjectRulesTests {
    @Test func loggingTypesStayInModuleLoggingDirectories() throws {
        let report = try RuleTestHarness(repositoryProjectRules).evaluate(
            VirtualRepository {
                VirtualSourceFile.swift(
                    "Where/Where/Sources/Logging/WhereAppLog.swift",
                    component: WhereComponent.app,
                    source: "enum WhereAppLog {}",
                )
                VirtualSourceFile.swift(
                    "Throw/ThrowCore/Sources/Logging/ThrowLog.swift",
                    component: ThrowComponent.throwCore,
                    source: "enum ThrowLog {}",
                )
                VirtualSourceFile.swift(
                    "Throw/ThrowUI/Sources/Model/RogueLog.swift",
                    component: ThrowComponent.throwUI,
                    source: "enum RogueLog {}",
                )
            },
        )

        let violation = try #require(report.violations.first)
        #expect(report.violations.count == 1)
        #expect(violation.rule.id == "repository.logging_type_ownership")
        #expect(violation.path == "Throw/ThrowUI/Sources/Model/RogueLog.swift")
    }
}

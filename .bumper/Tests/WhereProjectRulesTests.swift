import BumperBowlingCore
import BumperBowlingTestSupport
import Testing

@Suite("Where project rules")
struct WhereProjectRulesTests {
    @Test
    func `production store opens at process composition roots`() throws {
        let allowed = try evaluate(
            path: "Where/WhereUI/Sources/Launch/WhereLaunch.swift",
            component: .whereUI,
            source: "func open() throws { _ = try SwiftDataStore.make() }"
        )
        let rejectedPath: RelativeFilePath =
            "Where/WhereUI/Sources/Model/CompetingStoreOwner.swift"
        let rejected = try evaluate(
            path: rejectedPath,
            component: .whereUI,
            source: "func open() throws { _ = try SwiftDataStore.make() }"
        )

        #expect(allowed.violations.isEmpty)
        let violation = try #require(rejected.violations.first)
        #expect(rejected.violations.count == 1)
        #expect(violation.rule.id == "where.production_store_opening")
        #expect(violation.path == rejectedPath)
        #expect(violation.location != nil)
        #expect(
            violation.evidence == ViolationEvidence(
                observed: "SwiftDataStore.make in \(rejectedPath.rawValue)",
                expectation: "open the production store in WhereLaunch or ShareEvidenceModel"
            )
        )
    }

    @Test
    func `unsafe isolation stays in documented lifecycle owners`() throws {
        let allowed = try evaluate(
            path: "Where/WhereUI/Sources/Model/WhereSession.swift",
            component: .whereUI,
            source: "final class Session { nonisolated(unsafe) var task: Task<Void, Never>? }"
        )
        let rejectedPath: RelativeFilePath =
            "Where/WhereUI/Sources/Model/CompetingSession.swift"
        let rejected = try evaluate(
            path: rejectedPath,
            component: .whereUI,
            source: "final class Session { nonisolated(unsafe) var task: Task<Void, Never>? }"
        )

        #expect(allowed.violations.isEmpty)
        let violation = try #require(rejected.violations.first)
        #expect(rejected.violations.count == 1)
        #expect(violation.rule.id == "where.checked_concurrency_boundaries")
        #expect(violation.path == rejectedPath)
        #expect(violation.location != nil)
    }

    @Test
    func `preconcurrency is not a production escape hatch`() throws {
        let path: RelativeFilePath =
            "Where/WhereCore/Sources/LegacyDependency.swift"
        let report = try evaluate(
            path: path,
            component: .whereCore,
            source: "@preconcurrency import Foundation"
        )

        let violation = try #require(report.violations.first)
        #expect(report.violations.count == 1)
        #expect(violation.rule.id == "where.checked_concurrency_boundaries")
        #expect(violation.path == path)
        #expect(violation.location != nil)
    }

    @Test
    func `WhereServices assembly stays in Core and preview support`() throws {
        let core = try evaluate(
            path: "Where/WhereCore/Sources/WhereServices.swift",
            component: .whereCore,
            source: "func assemble() { _ = WhereServices() }"
        )
        let preview = try evaluate(
            path: "Where/WhereUI/Sources/Preview/PreviewSupport.swift",
            component: .whereUI,
            source: "func preview() { _ = WhereServices() }"
        )
        let rejectedPath: RelativeFilePath =
            "Where/WhereIntents/Sources/CompetingServices.swift"
        let rejected = try evaluate(
            path: rejectedPath,
            component: .whereIntents,
            source: "func assemble() { _ = WhereServices() }"
        )

        #expect(core.violations.isEmpty)
        #expect(preview.violations.isEmpty)
        let violation = try #require(rejected.violations.first)
        #expect(rejected.violations.count == 1)
        #expect(violation.rule.id == "where.services_composition_ownership")
        #expect(violation.path == rejectedPath)
    }

    @Test
    func `only WhereLaunch constructs the live location source`() throws {
        let allowed = try evaluate(
            path: "Where/WhereUI/Sources/Launch/WhereLaunch.swift",
            component: .whereUI,
            source: "func assemble() { _ = CoreLocationSource() }"
        )
        let rejectedPath: RelativeFilePath =
            "Where/WhereIntents/Sources/CompetingLocationSource.swift"
        let rejected = try evaluate(
            path: rejectedPath,
            component: .whereIntents,
            source: "func assemble() { _ = CoreLocationSource() }"
        )

        #expect(allowed.violations.isEmpty)
        let violation = try #require(rejected.violations.first)
        #expect(rejected.violations.count == 1)
        #expect(violation.rule.id == "where.live_location_source_ownership")
        #expect(violation.path == rejectedPath)
    }

    @Test
    func `Log event types stay in logging directories`() throws {
        let allowed = try evaluate(
            path: "Where/WhereUI/Sources/Logging/ScreenLog.swift",
            component: .whereUI,
            source: "enum ScreenLog {}"
        )
        let rejectedPath: RelativeFilePath =
            "Where/WhereUI/Sources/Model/ScreenLog.swift"
        let rejected = try evaluate(
            path: rejectedPath,
            component: .whereUI,
            source: "enum ScreenLog {}"
        )

        #expect(allowed.violations.isEmpty)
        let violation = try #require(rejected.violations.first)
        #expect(rejected.violations.count == 1)
        #expect(violation.rule.id == "where.logging_type_ownership")
        #expect(violation.path == rejectedPath)
    }

    @Test
    func `WhereIntents uses its aggregation-aligned calendar`() throws {
        let allowed = try evaluate(
            path: "Where/WhereIntents/Sources/CalendarUse.swift",
            component: .whereIntents,
            source: "let calendar = Calendar.whereIntents"
        )
        let rejectedPath: RelativeFilePath =
            "Where/WhereIntents/Sources/DriftingCalendar.swift"
        let rejected = try evaluate(
            path: rejectedPath,
            component: .whereIntents,
            source: "let calendar = Calendar.current"
        )
        let ordinaryUI = try evaluate(
            path: "Where/WhereUI/Sources/CalendarUse.swift",
            component: .whereUI,
            source: "let calendar = Calendar.current"
        )

        #expect(allowed.violations.isEmpty)
        #expect(ordinaryUI.violations.isEmpty)
        let violation = try #require(rejected.violations.first)
        #expect(rejected.violations.count == 1)
        #expect(violation.rule.id == "where.intents_calendar")
        #expect(violation.path == rejectedPath)
        #expect(
            violation.evidence == ViolationEvidence(
                observed: "Calendar.current",
                expectation: "Calendar.whereIntents"
            )
        )
    }

    private func evaluate(
        path: RelativeFilePath,
        component: WhereComponent,
        source: String
    ) throws -> RuleReport {
        try RuleTestHarness(whereProjectRules).evaluate(
            VirtualRepository {
                VirtualSourceFile.swift(path, component: component, source: source)
            }
        )
    }
}

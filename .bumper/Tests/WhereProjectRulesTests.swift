import BumperBowlingCore
import BumperBowlingTestSupport
import Testing

struct WhereProjectRulesTests {
    @Test
    func `production store opens at process composition roots`() throws {
        let allowed = try evaluate(
            path: "Where/WhereUI/Sources/Launch/WhereLaunch.swift",
            component: .whereUI,
            source: "func open() throws { _ = try SwiftDataStore.make() }",
        )
        let rejectedPath: RelativeFilePath =
            "Where/WhereUI/Sources/Model/CompetingStoreOwner.swift"
        let rejected = try evaluate(
            path: rejectedPath,
            component: .whereUI,
            source: "func open() throws { _ = try SwiftDataStore.make() }",
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
                expectation: "open the production store in WhereLaunch or ShareEvidenceModel",
            ),
        )
    }

    @Test
    func `unsafe isolation stays in documented lifecycle owners`() throws {
        let allowed = try evaluate(
            path: "Where/WhereUI/Sources/Model/WhereSession.swift",
            component: .whereUI,
            source: "final class Session { nonisolated(unsafe) var task: Task<Void, Never>? }",
        )
        let rejectedPath: RelativeFilePath =
            "Where/WhereUI/Sources/Model/CompetingSession.swift"
        let rejected = try evaluate(
            path: rejectedPath,
            component: .whereUI,
            source: "final class Session { nonisolated(unsafe) var task: Task<Void, Never>? }",
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
            source: "@preconcurrency import Foundation",
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
            source: "func assemble() { _ = WhereServices() }",
        )
        let preview = try evaluate(
            path: "Where/WhereUI/Sources/Preview/PreviewSupport.swift",
            component: .whereUI,
            source: "func preview() { _ = WhereServices() }",
        )
        let rejectedPath: RelativeFilePath =
            "Where/WhereIntents/Sources/CompetingServices.swift"
        let rejected = try evaluate(
            path: rejectedPath,
            component: .whereIntents,
            source: "func assemble() { _ = WhereServices() }",
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
            source: "func assemble() { _ = CoreLocationSource() }",
        )
        let rejectedPath: RelativeFilePath =
            "Where/WhereIntents/Sources/CompetingLocationSource.swift"
        let rejected = try evaluate(
            path: rejectedPath,
            component: .whereIntents,
            source: "func assemble() { _ = CoreLocationSource() }",
        )

        #expect(allowed.violations.isEmpty)
        let violation = try #require(rejected.violations.first)
        #expect(rejected.violations.count == 1)
        #expect(violation.rule.id == "where.live_location_source_ownership")
        #expect(violation.path == rejectedPath)
    }

    @Test
    func `Where uses explicit Gregorian calendars`() throws {
        let intentsAllowed = try evaluate(
            path: "Where/WhereIntents/Sources/CalendarUse.swift",
            component: .whereIntents,
            source: "let calendar = Calendar.whereIntents",
        )
        let uiAllowed = try evaluate(
            path: "Where/WhereUI/Sources/CalendarUse.swift",
            component: .whereUI,
            source: "let calendar = Calendar(identifier: .gregorian)",
        )
        let intentsRejectedPath: RelativeFilePath =
            "Where/WhereIntents/Sources/DriftingCalendar.swift"
        let intentsRejected = try evaluate(
            path: intentsRejectedPath,
            component: .whereIntents,
            source: "let calendar = Calendar.current",
        )
        let uiRejectedPath: RelativeFilePath =
            "Where/WhereUI/Sources/DriftingCalendar.swift"
        let uiRejected = try evaluate(
            path: uiRejectedPath,
            component: .whereUI,
            source: "let calendar = Calendar.current",
        )

        #expect(intentsAllowed.violations.isEmpty)
        #expect(uiAllowed.violations.isEmpty)
        let intentsViolation = try #require(intentsRejected.violations.first)
        #expect(intentsRejected.violations.count == 1)
        #expect(intentsViolation.rule.id == "where.gregorian_calendar")
        #expect(intentsViolation.path == intentsRejectedPath)
        #expect(
            intentsViolation.evidence == ViolationEvidence(
                observed: "Calendar.current",
                expectation: "an injected Gregorian calendar or Calendar.whereIntents",
            ),
        )
        let uiViolation = try #require(uiRejected.violations.first)
        #expect(uiRejected.violations.count == 1)
        #expect(uiViolation.rule.id == "where.gregorian_calendar")
        #expect(uiViolation.path == uiRejectedPath)
    }

    @Test
    func `WhereStore mutations stay inside perform transactions`() throws {
        let allowed = try evaluate(
            path: "Where/WhereCore/Sources/Journal.swift",
            component: .whereCore,
            source: "func save() async throws { try await store.perform { try await store.add(sample: sample) } }",
        )
        let currentGenerationAllowed = try evaluate(
            path: "Where/WhereCore/Sources/CurrentGenerationJournal.swift",
            component: .whereCore,
            source: "func save() async throws { try await store.performInCurrentGeneration { try await store.add(sample: sample) } }",
        )
        let rejectedPath: RelativeFilePath =
            "Where/WhereCore/Sources/CompetingWriter.swift"
        let rejected = try evaluate(
            path: rejectedPath,
            component: .whereCore,
            source: "func save() async throws { try await store.add(sample: sample) }",
        )

        #expect(allowed.violations.isEmpty)
        #expect(currentGenerationAllowed.violations.isEmpty)
        let violation = try #require(rejected.violations.first)
        #expect(rejected.violations.count == 1)
        #expect(violation.rule.id == "where.store_transaction_boundary")
        #expect(violation.path == rejectedPath)
    }

    @Test
    func `AppShortcutsProvider stays in the app target`() throws {
        let allowed = try evaluate(
            path: "Where/Where/Sources/WhereShortcuts.swift",
            component: .app,
            source: "struct WhereShortcuts: AppShortcutsProvider {}",
        )
        let rejectedPath: RelativeFilePath =
            "Where/WhereIntents/Sources/WhereShortcuts.swift"
        let rejected = try evaluate(
            path: rejectedPath,
            component: .whereIntents,
            source: "struct WhereShortcuts: AppShortcutsProvider {}",
        )

        #expect(allowed.violations.isEmpty)
        let violation = try #require(rejected.violations.first)
        #expect(rejected.violations.count == 1)
        #expect(violation.rule.id == "where.app_shortcuts_provider_ownership")
        #expect(violation.path == rejectedPath)
    }

    @Test
    func `production logging uses typed facades`() throws {
        let allowed = try evaluate(
            path: "Where/WhereCore/Sources/Worker.swift",
            component: .whereCore,
            source: "func run() { WhereLog.root(WorkerLog.self) { .completed } }",
        )
        let printRejected = try evaluate(
            path: "Where/WhereCore/Sources/PrintingWorker.swift",
            component: .whereCore,
            source: "func run() { print(\"done\") }",
        )
        let osLogRejected = try evaluate(
            path: "Where/WhereUI/Sources/LoggingScreen.swift",
            component: .whereUI,
            source: "import OSLog\nstruct LoggingScreen {}",
        )

        #expect(allowed.violations.isEmpty)
        #expect(printRejected.violations.map(\.rule.id) == ["where.logging_facade"])
        #expect(osLogRejected.violations.map(\.rule.id) == ["where.logging_facade"])
    }

    @Test
    func `previewable components include an in-file preview`() throws {
        let allowed = try evaluate(
            path: "Where/WhereUI/Sources/PreviewedView.swift",
            component: .whereUI,
            source: "struct PreviewedView: View {}\n#Preview { PreviewedView() }",
        )
        let rejectedPath: RelativeFilePath =
            "Where/WhereUI/Sources/UnpreviewedView.swift"
        let rejected = try evaluate(
            path: rejectedPath,
            component: .whereUI,
            source: "struct UnpreviewedView: View {}",
        )
        let coreView = try evaluate(
            path: "Where/WhereCore/Sources/DomainView.swift",
            component: .whereCore,
            source: "struct DomainView: View {}",
        )

        #expect(allowed.violations.isEmpty)
        #expect(coreView.violations.isEmpty)
        let violation = try #require(rejected.violations.first)
        #expect(rejected.violations.count == 1)
        #expect(violation.rule.id == "where.preview_coverage")
        #expect(violation.path == rejectedPath)
    }

    private func evaluate(
        path: RelativeFilePath,
        component: WhereComponent,
        source: String,
    ) throws -> RuleReport {
        try RuleTestHarness(whereProjectRules).evaluate(
            VirtualRepository {
                VirtualSourceFile.swift(path, component: component, source: source)
            },
        )
    }
}

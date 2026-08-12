import PeriscopeCore
import Testing
@testable import WhereIntents

/// Covers the intents surface's logging vocabulary: the shared scope, the span
/// names recorded history groups timings by, and the per-intent budgets that
/// decide when a `perform()` is late.
struct WhereIntentsLogTests {
    // MARK: - Scope

    @Test func theWholeSurfaceSharesOneLoggerScope() {
        // One derivation, so a span and an event from the same intent can't land
        // in two scopes.
        #expect(WhereIntentsLog.logger.primaryScope.name == "WhereIntents")
    }

    // MARK: - Span names

    @Test func performSpansAreNamedAfterTheIntentNotItsSwiftCase() {
        // Reflection would render this `perform(WhereIntents.IntentName.logDay)`,
        // leaking the module into the name the span tools group timings by.
        #expect(
            String(describing: WhereIntentsLog.SpanName.perform(.logDay)) == "perform(log-day)",
        )
        #expect(String(describing: WhereIntentsLog.SpanName.awaitServices) == "awaitServices")
    }

    @Test func everyIntentHasAHyphenatedNameOfItsOwn() {
        // A new intent must earn a name rather than inherit one — duplicates
        // would pool two intents' timings under a single span.
        let names = WhereIntentsLog.IntentName.allCases.map(\.rawValue)
        #expect(Set(names).count == WhereIntentsLog.IntentName.allCases.count)
        #expect(names.allSatisfy { !$0.isEmpty && $0 == $0.lowercased() })
    }

    // MARK: - Budgets

    @Test func everyIntentDeclaresARealBudget() {
        // A zero (or negative) budget would fire the overdue warning immediately
        // on every invocation, which is the same as having no signal at all.
        #expect(WhereIntentsLog.IntentName.allCases.allSatisfy { $0.budget > .zero })
    }

    @Test func onlyTheSlowByNatureIntentGetsSlack() {
        // A trip backfills a whole range; a single aggregated read has no such
        // excuse, so it stays on the tight default.
        let read = WhereIntentsLog.IntentName.todayRegions.budget
        #expect(WhereIntentsLog.IntentName.logTrip.budget > read)
        #expect(WhereIntentsLog.IntentName.logDay.budget == read)
    }
}

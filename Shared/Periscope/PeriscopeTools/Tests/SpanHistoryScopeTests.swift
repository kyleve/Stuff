import Foundation
import PeriscopeCore
@testable import PeriscopeTools
import Testing

/// Covers which sessions each span-history scope admits, and which scopes a
/// given store can offer at all.
struct SpanHistoryScopeTests {
    private func session(
        _ attributes: [LogSessionAttributeKey: String],
    ) -> LogSession {
        makeSession(attributes: attributes)
    }

    @Test func allAdmitsEverySessionWithoutBuildingASet() {
        let sessions = [session([:]), session([.optimizationLevel: "-O"])]
        #expect(
            SpanHistoryScope.all.sessionIDs(in: sessions, current: sessions[0]) == nil,
        )
    }

    @Test func currentSessionAdmitsOnlyThatSession() {
        let sessions = [session([:]), session([:])]
        #expect(
            SpanHistoryScope.currentSession.sessionIDs(in: sessions, current: sessions[1])
                == [sessions[1].id],
        )
    }

    @Test func sameOptimizationLevelAdmitsEverySessionBuiltThatWay() {
        let onone = session([.optimizationLevel: "-Onone"])
        let alsoOnone = session([.optimizationLevel: "-Onone"])
        let optimized = session([.optimizationLevel: "-O"])
        let sessions = [onone, alsoOnone, optimized]

        #expect(
            SpanHistoryScope.sameOptimizationLevel.sessionIDs(in: sessions, current: onone)
                == [onone.id, alsoOnone.id],
        )
    }

    /// A session that never named its optimization level isn't comparable to
    /// one that did, so it doesn't group with them.
    @Test func sameOptimizationLevelExcludesSessionsThatNamedNoLevel() {
        let optimized = session([.optimizationLevel: "-O"])
        let unstated = session([:])

        #expect(
            SpanHistoryScope.sameOptimizationLevel.sessionIDs(
                in: [optimized, unstated],
                current: optimized,
            ) == [optimized.id],
        )
    }

    /// The scope can't be resolved, so it admits nothing rather than widening
    /// back to every build — a label saying one thing over data saying another
    /// is the failure mode worth avoiding here.
    @Test func unresolvableScopesAdmitNothing() {
        let sessions = [session([:])]
        #expect(
            SpanHistoryScope.currentSession.sessionIDs(in: sessions, current: nil) == [],
        )
        #expect(
            SpanHistoryScope.sameOptimizationLevel.sessionIDs(
                in: sessions,
                current: sessions[0],
            ) == [],
        )
    }

    @Test func onlyAllResolvesWithoutACurrentSession() {
        #expect(SpanHistoryScope.all.resolvable(current: nil))
        #expect(!SpanHistoryScope.currentSession.resolvable(current: nil))
        #expect(!SpanHistoryScope.sameOptimizationLevel.resolvable(current: nil))
    }

    @Test func optimizationScopeNeedsTheCurrentSessionToNameALevel() {
        #expect(!SpanHistoryScope.sameOptimizationLevel.resolvable(current: session([:])))
        #expect(
            SpanHistoryScope.sameOptimizationLevel
                .resolvable(current: session([.optimizationLevel: "-Onone"])),
        )
    }

    @Test func everyScopeHasADisplayName() {
        for scope in SpanHistoryScope.allCases {
            #expect(!scope.displayName.isEmpty)
        }
    }
}

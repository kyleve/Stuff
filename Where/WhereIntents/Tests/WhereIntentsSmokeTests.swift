import Testing
@testable import WhereIntents

/// Placeholder smoke coverage so the hosted `WhereIntentsTests` bundle has a
/// source to build while the real per-type suites are added. Replaced by the
/// entity/enum/intent suites.
struct WhereIntentsSmokeTests {
    @Test func moduleLoads() {
        #expect(Bool(true))
    }
}

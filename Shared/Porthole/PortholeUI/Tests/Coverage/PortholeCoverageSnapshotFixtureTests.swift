#if canImport(UIKit)
    @testable import PortholeUI
    import Testing

    @MainActor
    struct PortholeCoverageSnapshotFixtureTests {
        @Test func readinessWaitsForTheSamePageThatSurvivesRehosting() async {
            let fixture = PortholeCoverageSnapshotFixture(module: nil)
            async let measurement: Void = fixture.prepare()
            async let capture: Void = fixture.prepare()
            _ = await (measurement, capture)
            guard case let .loaded(.modules(page)) = fixture.model.state
            else { Issue.record("Readiness did not produce the module page"); return }
            #expect(page.items == PortholeCoverageSnapshotServices.modules)
            fixture.model.cancel()
            await fixture.model.loadIfNeeded()
            await fixture.prepare()
            guard case let .loaded(.modules(rehosted)) = fixture.model.state
            else { Issue.record("Rehosting discarded coverage"); return }
            #expect(rehosted == page)
        }
    }
#endif

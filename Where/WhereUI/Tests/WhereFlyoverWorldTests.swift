#if DEBUG
    import Testing
    @testable import WhereUI

    @MainActor
    struct WhereFlyoverWorldTests {
        @Test func buildsASeededSiblingWithoutActivatingIt() async throws {
            let world = try await WhereFlyoverWorld.build()

            #expect(world.scope.logStore != nil)
            #expect(world.scope.preferences.hasOnboarded)
            #expect(world.scope.preferences.wantsTracking)
            #expect(world.model.isInDemoMode == false)
            #expect(world.model.activeScope !== world.scope)
            #expect(world.report.report?.days.isEmpty == false)
        }
    }
#endif

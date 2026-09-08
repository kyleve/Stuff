#if DEBUG
    import PeriscopeCore
    import Testing
    @testable import WhereUI

    @MainActor
    struct WhereFlyoverWorldTests {
        @Test func buildsASeededSiblingWithoutActivatingIt() async throws {
            let world = try await WhereFlyoverWorld.build()

            #expect(world.scope.logStore != nil)
            #expect(world.scope.preferences.hasOnboarded)
            #expect(world.model.isInDemoMode == false)
            #expect(world.model.activeScope !== world.scope)
            #expect(world.report.report?.days.isEmpty == false)
        }

        @Test func keepsNativeSpansLiveAndWebExportSpansSynthetic() async throws {
            let nativeWorld = try await WhereFlyoverWorld.build()
            #expect(nativeWorld.openSpansLogSystem === Periscope.shared)

            let exportWorld = try await WhereFlyoverWorld.buildForWebExport()
            #expect(exportWorld.openSpansLogSystem !== Periscope.shared)
        }
    }
#endif

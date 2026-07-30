#if DEBUG
    import Testing
    @testable import WhereUI

    struct DeveloperToolTests {
        @Test func preSessionMenuContainsOnlyProcessIndependentTools() {
            #expect(
                DeveloperTool.available(hasLogStore: false, hasInspector: false)
                    == [.openSpans, .regionMap],
            )
        }

        @Test func attachedSessionMenuContainsEveryToolInRouteOrder() {
            #expect(
                DeveloperTool.available(hasLogStore: true, hasInspector: true)
                    == [.logs, .openSpans, .swiftDataInspector, .regionMap],
            )
        }

        @Test func dependenciesGateTheirOwnRouteIndependently() {
            #expect(
                DeveloperTool.available(hasLogStore: true, hasInspector: false)
                    == [.logs, .openSpans, .regionMap],
            )
            #expect(
                DeveloperTool.available(hasLogStore: false, hasInspector: true)
                    == [.openSpans, .swiftDataInspector, .regionMap],
            )
        }
    }
#endif

#if DEBUG
    import Testing
    @testable import WhereUI

    struct DeveloperDestinationTests {
        @Test func preSessionMenuContainsOnlyProcessIndependentTools() {
            #expect(
                DeveloperDestination.available(hasLogStore: false, hasInspector: false)
                    == [.tool(.openSpans), .flyover, .tool(.regionMap)],
            )
        }

        @Test func attachedSessionMenuContainsEveryToolInRouteOrder() {
            #expect(
                DeveloperDestination.available(hasLogStore: true, hasInspector: true)
                    == [
                        .tool(.logs),
                        .tool(.openSpans),
                        .tool(.swiftDataInspector),
                        .flyover,
                        .tool(.regionMap),
                    ],
            )
        }

        @Test func dependenciesGateTheirOwnRouteIndependently() {
            #expect(
                DeveloperDestination.available(hasLogStore: true, hasInspector: false)
                    == [.tool(.logs), .tool(.openSpans), .flyover, .tool(.regionMap)],
            )
            #expect(
                DeveloperDestination.available(hasLogStore: false, hasInspector: true)
                    == [
                        .tool(.openSpans),
                        .tool(.swiftDataInspector),
                        .flyover,
                        .tool(.regionMap),
                    ],
            )
        }
    }
#endif

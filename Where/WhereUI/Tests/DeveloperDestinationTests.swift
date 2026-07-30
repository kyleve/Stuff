#if DEBUG
    import Testing
    @testable import WhereUI

    struct DeveloperDestinationTests {
        @Test func preSessionMenuContainsOnlyProcessIndependentTools() {
            #expect(
                DeveloperDestination.available(hasLogStore: false)
                    == [.tool(.openSpans), .flyover, .tool(.regionMap)],
            )
        }

        @Test func attachedLogStoreAddsOnlyTheLogsTool() {
            #expect(
                DeveloperDestination.available(hasLogStore: true)
                    == [
                        .tool(.logs),
                        .tool(.openSpans),
                        .flyover,
                        .tool(.regionMap),
                    ],
            )
        }
    }
#endif

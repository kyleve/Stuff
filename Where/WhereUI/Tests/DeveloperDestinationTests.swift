#if DEBUG
    import Testing
    @testable import WhereUI

    struct DeveloperDestinationTests {
        @Test func loggingDiagnosticsRemainAvailableBeforeTheStore() {
            #expect(
                DeveloperDestination.available
                    == [
                        .tool(.logs),
                        .tool(.openSpans),
                        .flyover,
                        .tool(.regionMap),
                        .tool(.crashTesting),
                    ],
            )
        }
    }
#endif

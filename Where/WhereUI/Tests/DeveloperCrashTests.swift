#if DEBUG
    import Testing
    @testable import WhereUI

    struct DeveloperCrashTests {
        @Test func exposesEveryCrashMechanismInAStableOrder() {
            #expect(
                DeveloperCrash.allCases == [
                    .swiftFatalError,
                    .arrayBounds,
                    .objectiveCException,
                    .abortSignal,
                    .invalidMemoryAccess,
                ],
            )
        }
    }
#endif

#if DEBUG
    import Testing
    @testable import WhereUI

    @MainActor
    struct WhereFlyoverLoaderTests {
        @Test func loadsTheCompletedCatalogIntoSessionState() async {
            let loader = WhereFlyoverLoader()

            await loader.load()

            guard case let .loaded(catalog) = loader.state else {
                Issue.record("Expected the Flyover catalog to finish loading.")
                return
            }
            #expect(catalog.isValid)
            #expect(catalog.screens.count == WhereFlyoverCatalog.registrations.count)
        }
    }
#endif

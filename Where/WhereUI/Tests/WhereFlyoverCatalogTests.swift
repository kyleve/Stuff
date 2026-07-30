#if DEBUG
    import Testing
    @testable import WhereUI

    @MainActor
    struct WhereFlyoverCatalogTests {
        @Test func registersEveryDeclaredScreenExactlyOnce() async throws {
            let world = try await WhereFlyoverWorld.build()
            let catalog = WhereFlyoverCatalog.make(world: world)
            let registered = catalog.screens.map(\.id)

            #expect(catalog.isValid)
            #expect(Set(registered) == Set(WhereFlyoverScreenID.allCases))
            #expect(registered.count == WhereFlyoverScreenID.allCases.count)
        }

        @Test func recordsOnlyForwardPushAndModalRoutes() async throws {
            let world = try await WhereFlyoverWorld.build()
            let catalog = WhereFlyoverCatalog.make(world: world)

            #expect(catalog.transitions.isEmpty == false)
            #expect(catalog.transitions.allSatisfy { transition in
                switch transition.kind {
                    case .push, .modal: true
                }
            })
        }
    }
#endif

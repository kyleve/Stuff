#if DEBUG
    import Testing
    @testable import WhereUI

    @MainActor
    struct WhereFlyoverCatalogTests {
        @Test func assemblesEveryColocatedRegistrationExactlyOnce() async throws {
            let world = try await WhereFlyoverWorld.build()
            let catalog = WhereFlyoverCatalog.make(world: world)
            let registered = catalog.screens.map(\.id)
            let declared = WhereFlyoverCatalog.registrations.map(\.id)

            #expect(catalog.isValid)
            #expect(Set(registered) == Set(declared))
            #expect(registered.count == declared.count)
            #expect(declared.count == Set(declared).count)
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

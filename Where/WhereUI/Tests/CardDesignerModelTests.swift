#if DEBUG
    import Foundation
    import Testing
    @testable import WhereUI

    @MainActor
    struct CardDesignerModelTests {
        @Test func persistsTheDraftButNotTheAppWideOverride() throws {
            let (store, suite) = try isolatedStore()
            defer { store.removePersistentDomain(forName: suite) }
            let key = "card-designer"
            let model = CardDesignerModel(store: store, key: key)
            model.configuration.regular.cornerRadius = 39
            model.appliesToApp = true

            let reloaded = CardDesignerModel(store: store, key: key)

            #expect(reloaded.configuration.regular.cornerRadius == 39)
            #expect(reloaded.appliesToApp == false)
        }

        @Test func corruptPersistenceSurfacesAnErrorAndUsesDefaults() throws {
            let (store, suite) = try isolatedStore()
            defer { store.removePersistentDomain(forName: suite) }
            let key = "card-designer"
            store.set(Data("not json".utf8), forKey: key)

            let model = CardDesignerModel(store: store, key: key)

            #expect(model.configuration == .standard)
            #expect(model.persistenceError != nil)
        }

        @Test func resetAllReplacesCorruptPersistenceWithDefaults() throws {
            let (store, suite) = try isolatedStore()
            defer { store.removePersistentDomain(forName: suite) }
            let key = "card-designer"
            store.set(Data("not json".utf8), forKey: key)
            let model = CardDesignerModel(store: store, key: key)

            model.resetAll()
            let reloaded = CardDesignerModel(store: store, key: key)

            #expect(model.persistenceError == nil)
            #expect(reloaded.configuration == .standard)
            #expect(reloaded.persistenceError == nil)
        }

        @Test func resetVariantLeavesTheOtherVariantUntouched() throws {
            let (store, suite) = try isolatedStore()
            defer { store.removePersistentDomain(forName: suite) }
            let model = CardDesignerModel(store: store, key: "card-designer")
            model.configuration.regular.cornerRadius = 42
            model.configuration.compact.cornerRadius = 31

            model.reset(.regular)

            #expect(model.configuration.regular == CardDesignerConfiguration.standard.regular)
            #expect(model.configuration.compact.cornerRadius == 31)
        }

        @Test func resetAllRestoresEveryToken() throws {
            let (store, suite) = try isolatedStore()
            defer { store.removePersistentDomain(forName: suite) }
            let model = CardDesignerModel(store: store, key: "card-designer")
            model.configuration.shared.darkSecurityPrint.whiteMix = 0.2
            model.configuration.compact.sheen.intensity = 0.9

            model.resetAll()

            #expect(model.configuration == .standard)
        }

        private func isolatedStore() throws -> (store: UserDefaults, suite: String) {
            let suite = "CardDesignerModelTests-\(UUID().uuidString)"
            let store = try #require(UserDefaults(suiteName: suite))
            return (store, suite)
        }
    }
#endif

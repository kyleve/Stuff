#if DEBUG
    import Foundation
    @_spi(Testing) import LedgerCore

    /// Preview fixtures. Sessions are backed by a stub token source and a
    /// scripted dashboard provider — they never read the real Cursor state,
    /// touch the network, or write Application Support.
    @MainActor
    enum PreviewSupport {
        /// A session already showing spend.
        static func loadedSession() -> LedgerSession {
            let provider = ScriptedDashboardProvider(.success(
                summary: .fixture(
                    onDemandCents: 315_609,
                    membershipType: "ultra",
                    includedUsed: 40000,
                    includedLimit: 40000,
                ),
                invoiceCentsByMonth: [
                    1: 120_000,
                    2: 98000,
                    3: 210_000,
                    4: 175_000,
                    5: 260_000,
                    6: 288_000,
                ],
            ))
            let session = session(
                provider: provider,
                autoToken: SessionToken(cookieValue: "user_preview::jwt"),
            )
            session.refresh()
            return session
        }

        private static func session(
            provider: any DashboardProvider,
            autoToken: SessionToken?,
        ) -> LedgerSession {
            let base = FileManager.default.temporaryDirectory
                .appendingPathComponent("LedgerPreview-\(UUID().uuidString)")
            let store = LedgerConfigStore(directory: base)
            try? store.save(LedgerConfiguration(refreshInterval: 900))
            let services = LedgerServices(
                configStore: store,
                keychain: InMemoryKeychainStore(),
                tokenSource: StubTokenSource(token: autoToken),
                provider: provider,
                loginItem: LoginItemController(),
            )
            return LedgerSession(services: services)
        }
    }
#endif

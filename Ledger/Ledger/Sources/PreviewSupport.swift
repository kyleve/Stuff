#if DEBUG
    import Foundation
    @_spi(Testing) import LedgerCore

    /// Preview fixtures. Sessions are backed by an in-memory Keychain and a
    /// scripted spend provider — they never touch the real Keychain, the
    /// network, or `~/Library/Application Support`.
    @MainActor
    enum PreviewSupport {
        /// A session already showing a member's spend.
        static func loadedSession() -> LedgerSession {
            let member = MemberSpend(
                userId: "user_preview",
                name: "Preview User",
                email: "you@company.com",
                spendCents: 4212,
                includedSpendCents: 8000,
                overallSpendCents: 12212,
                fastPremiumRequests: 143,
            )
            let session = session(
                provider: ScriptedSpendProvider(member: member),
                email: member.email,
            )
            session.refresh()
            return session
        }

        private static func session(provider: any SpendProvider, email: String?) -> LedgerSession {
            let base = FileManager.default.temporaryDirectory
                .appendingPathComponent("LedgerPreview-\(UUID().uuidString)")
            let store = LedgerConfigStore(directory: base)
            try? store.save(LedgerConfiguration(teamMemberEmail: email, refreshInterval: 900))
            let services = LedgerServices(
                configStore: store,
                keychain: InMemoryKeychainStore(secret: "preview-key"),
                provider: provider,
                loginItem: LoginItemController(),
            )
            return LedgerSession(services: services)
        }
    }
#endif

#if DEBUG
    import ForemanCore
    import Foundation

    /// Preview fixtures. Sessions are backed by throwaway temp directories —
    /// they never read the real config, spawn processes, or touch
    /// `~/Development`.
    @MainActor
    enum PreviewSupport {
        /// A session over an empty scan directory (the "no repos" state).
        static func emptySession() -> ForemanSession {
            session(repoNames: [])
        }

        /// A session with a few discovered repos across both sidebar sections:
        /// two enabled (one of them favorited) and a favorited-but-disabled one.
        static func populatedSession() -> ForemanSession {
            session(
                repoNames: ["Broadway", "Site", "Stuff"],
                enabled: ["Broadway", "Stuff"],
                favorites: ["Broadway", "Site"],
            )
        }

        private static func session(
            repoNames: [String],
            enabled: Set<String> = [],
            favorites: Set<String> = [],
        ) -> ForemanSession {
            let base = FileManager.default.temporaryDirectory
                .appendingPathComponent("ForemanPreview-\(UUID().uuidString)")
            let scanDirectory = base.appendingPathComponent("Development")
            do {
                for name in repoNames {
                    try FileManager.default.createDirectory(
                        at: scanDirectory.appendingPathComponent("\(name)/.git"),
                        withIntermediateDirectories: true,
                    )
                }
                if repoNames.isEmpty {
                    try FileManager.default.createDirectory(
                        at: scanDirectory,
                        withIntermediateDirectories: true,
                    )
                }
                var repos: [RepoID: RepoConfiguration] = [:]
                for name in enabled.union(favorites) {
                    let id = RepoID(rootURL: scanDirectory
                        .appendingPathComponent(name, isDirectory: true))
                    repos[id] = RepoConfiguration(
                        isEnabled: enabled.contains(name),
                        isFavorite: favorites.contains(name),
                        options: .standard,
                    )
                }
                let store = WorkerConfigStore(directory: base.appendingPathComponent("config"))
                try store.save(ForemanConfiguration(
                    scanDirectory: scanDirectory,
                    agentExecutable: nil,
                    repos: repos,
                ))
                let session = ForemanSession(services: ForemanServices(
                    configStore: store,
                    logDirectory: base.appendingPathComponent("logs"),
                ))
                // Populate the tree from the saved config (seeding
                // isEnabled/isFavorite) via a plain rescan — not start(), whose
                // launch restore would spawn real workers. Previews never spawn.
                session.rescan()
                return session
            } catch {
                fatalError("Preview fixture setup failed: \(error)")
            }
        }
    }
#endif

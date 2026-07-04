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

        /// A session with a few discovered repos, all stopped.
        static func populatedSession() -> ForemanSession {
            session(repoNames: ["Broadway", "Site", "Stuff"])
        }

        private static func session(repoNames: [String]) -> ForemanSession {
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
                let store = WorkerConfigStore(directory: base.appendingPathComponent("config"))
                try store.save(ForemanConfiguration(
                    scanDirectory: scanDirectory,
                    agentExecutable: nil,
                    enabledRepoIDs: [],
                    repoOptions: [:],
                ))
                let session = ForemanSession(
                    configStore: store,
                    supervisor: WorkerSupervisor(logDirectory: base.appendingPathComponent("logs")),
                )
                session.start()
                return session
            } catch {
                fatalError("Preview fixture setup failed: \(error)")
            }
        }
    }
#endif

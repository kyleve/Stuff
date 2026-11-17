#if DEBUG
    @testable import WhereUI

    /// One standard demo world for the noninteractive MainTabs and Device Layout Lab matrices.
    /// Do not use this owner for previews, user actions, or lifecycle/mutation tests.
    @MainActor
    final class SnapshotWorldFixture {
        static let shared = SnapshotWorldFixture()

        private let buildWorld: @MainActor () async throws -> WhereFlyoverWorld
        private var worldTask: Task<WhereFlyoverWorld, Error>?

        init(buildWorld: @escaping @MainActor () async throws
            -> WhereFlyoverWorld = WhereFlyoverWorld.build)
        {
            self.buildWorld = buildWorld
        }

        func load() async throws -> WhereFlyoverWorld {
            try Task.checkCancellation()
            let task: Task<WhereFlyoverWorld, Error>
            if let worldTask {
                task = worldTask
            } else {
                // Initialization belongs to the fixture, so an unmounted capture cannot
                // cancel it for other callers. MainActor installs the task before it runs.
                task = Task {
                    do {
                        return try await buildWorld()
                    } catch {
                        worldTask = nil
                        throw error
                    }
                }
                worldTask = task
            }
            let world = try await task.value
            try Task.checkCancellation()
            return world
        }
    }
#endif

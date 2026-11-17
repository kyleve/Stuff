#if DEBUG
    import Observation

    /// Completion of the mounted task in noninteractive shell fixtures. These fix
    /// their scene phase and data, so no foreground activation supersedes that task.
    @MainActor
    final class MainTabsSnapshotReadiness {
        @MainActor
        @Observable
        final class Mount {
            var didActivate = false
        }

        private var pendingMount: Mount?
        private var mountWaiter: AsyncStream<Mount>.Continuation?

        func registerMount() -> Mount {
            let mount = Mount()
            if let mountWaiter {
                mountWaiter.yield(mount)
            } else {
                pendingMount = mount
            }
            return mount
        }

        func waitForActivation() async {
            guard let mount = await nextMount() else { return }
            for await ready in Observations({ mount.didActivate }) {
                if ready || Task.isCancelled { return }
            }
        }

        private func nextMount() async -> Mount? {
            if let pendingMount {
                self.pendingMount = nil
                return pendingMount
            }
            precondition(mountWaiter == nil, "MainTabs snapshot hooks must run serially")
            let (mounts, continuation) = AsyncStream.makeStream(
                of: Mount.self,
                bufferingPolicy: .bufferingOldest(1),
            )
            mountWaiter = continuation
            defer {
                mountWaiter = nil
                continuation.finish()
            }
            var iterator = mounts.makeAsyncIterator()
            return await iterator.next()
        }
    }
#endif

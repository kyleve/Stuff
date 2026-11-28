#if DEBUG
    import Testing
    @testable import WhereUI

    @MainActor
    @Suite(.timeLimit(.minutes(1)))
    struct SnapshotWorldFixtureTests {
        @Test func cancelledCaptureDoesNotCancelAnotherCaptureOrRebuild() async {
            let world = WhereFlyoverWorld.preview()
            let started = AsyncStream.makeStream(of: Void.self)
            let release = AsyncStream.makeStream(of: Void.self)
            let joined = AsyncStream.makeStream(of: Void.self)
            var builds = 0
            let fixture = SnapshotWorldFixture {
                builds += 1
                started.continuation.yield()
                await release.stream.first { _ in true }
                try Task.checkCancellation()
                return world
            }
            let first = WhereDemoWorldModel(buildWorld: fixture.load)
            let second = WhereDemoWorldModel(buildWorld: fixture.load)
            let firstLoad = Task { await first.load() }
            await started.stream.first { _ in true }
            let secondLoad = Task {
                joined.continuation.yield()
                await second.load()
            }
            await joined.stream.first { _ in true }
            firstLoad.cancel()
            release.continuation.yield()
            await firstLoad.value
            await secondLoad.value
            guard case .idle = first.state, case let .loaded(loaded) = second.state else {
                Issue.record("Cancellation must leave only the canceled capture idle")
                return
            }
            #expect(loaded === world)
            await first.load()
            guard case let .loaded(reloaded) = first.state else {
                Issue.record("A later capture must reuse the completed initialization")
                return
            }
            #expect(reloaded === world)
            #expect(builds == 1)
        }

        @Test func failedInitializationCanRetry() async {
            struct BuildFailure: Error {}
            let world = WhereFlyoverWorld.preview()
            var builds = 0
            let fixture = SnapshotWorldFixture {
                builds += 1
                if builds == 1 {
                    throw BuildFailure()
                }
                return world
            }
            let model = WhereDemoWorldModel(buildWorld: fixture.load)
            await model.load()
            guard case let .failed(error) = model.state else {
                Issue.record("Initialization failures must remain visible")
                return
            }
            #expect(error is BuildFailure)
            model.retry()
            await model.load()
            guard case let .loaded(loaded) = model.state else {
                Issue.record("Retry must start a new initialization after failure")
                return
            }
            #expect(loaded === world)
            #expect(builds == 2)
        }

        @Test func alreadyCancelledCallerDoesNotStartInitialization() async throws {
            var builds = 0
            let fixture = SnapshotWorldFixture {
                builds += 1
                return WhereFlyoverWorld.preview()
            }
            let load = Task { try await fixture.load() }
            load.cancel()
            await #expect(throws: CancellationError.self) { try await load.value }
            #expect(builds == 0)
            _ = try await fixture.load()
            #expect(builds == 1)
        }
    }
#endif

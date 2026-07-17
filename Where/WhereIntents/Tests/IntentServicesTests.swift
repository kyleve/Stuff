import Foundation
import Testing
@_spi(Testing) import WhereCore
@testable import WhereIntents

/// The intent layer's services handoff: `current()` returns the installed
/// stack, parks until one is installed (never self-assembling a store — the
/// launch's open must stay the process's only one), honors cancellation while
/// parked, and a later install replaces the cached stack. Each test builds its
/// own `IntentServices` — the app-registered instance (see `AppDelegate` /
/// `AppDependencyManager`) is never touched.
struct IntentServicesTests {
    private func makeStack() throws -> WhereServices {
        try IntentTestSupport.services(store: SwiftDataStore.inMemory())
    }

    @Test func currentReturnsTheInstalledStack() async throws {
        let handoff = IntentServices()
        let stack = try makeStack()
        await handoff.install(stack)

        let resolved = try await handoff.current()

        #expect(resolved.modelContainer != nil)
        #expect(resolved.modelContainer === stack.modelContainer)
    }

    @Test func currentParksUntilAStackIsInstalled() async throws {
        let handoff = IntentServices()
        let parked = Task { try await handoff.current() }
        // Condition, not timing: the waiter is provably parked before the
        // install that must resume it.
        try await waitUntil { await handoff.waiterCount == 1 }

        let stack = try makeStack()
        await handoff.install(stack)

        let resolved = try await parked.value
        #expect(resolved.modelContainer != nil)
        #expect(resolved.modelContainer === stack.modelContainer)
        #expect(await handoff.waiterCount == 0)
    }

    @Test func cancellingAParkedIntentThrowsAndUnparksIt() async throws {
        let handoff = IntentServices()
        let parked = Task { try await handoff.current() }
        try await waitUntil { await handoff.waiterCount == 1 }

        parked.cancel()

        await #expect(throws: CancellationError.self) { try await parked.value }
        try await waitUntil { await handoff.waiterCount == 0 }
    }

    @Test func aLaterInstallReplacesTheCachedStack() async throws {
        // A reset relaunch installs a fresh session's stack; later intents must
        // ride it, not the stale one.
        let handoff = IntentServices()
        let first = try makeStack()
        let second = try makeStack()
        await handoff.install(first)
        await handoff.install(second)

        let resolved = try await handoff.current()
        #expect(resolved.modelContainer === second.modelContainer)
        #expect(resolved.modelContainer !== first.modelContainer)
    }
}

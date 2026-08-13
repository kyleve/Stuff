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
        await handoff.install(stack, theme: .standard)

        let resolved = try await handoff.current()

        #expect(resolved.journal === stack.journal)
    }

    @Test func currentParksUntilAStackIsInstalled() async throws {
        let handoff = IntentServices()
        let parked = Task { try await handoff.current() }
        // Condition, not timing: the waiter is provably parked before the
        // install that must resume it.
        try await waitUntil { await handoff.waiterCount == 1 }

        let stack = try makeStack()
        await handoff.install(stack, theme: .standard)

        let resolved = try await parked.value
        #expect(resolved.journal === stack.journal)
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
        await handoff.install(first, theme: .standard)
        await handoff.install(second, theme: .alternate)

        let resolved = try await handoff.current()
        #expect(resolved.journal === second.journal)
        #expect(resolved.journal !== first.journal)
    }

    /// TLC property `AfterClearMustPark`: after `clear()`, a parked intent must
    /// resume on the next `install(_:)` rather than observing a cleared stack.
    @Test func clearWhileParkedResumesOnTheNextInstall() async throws {
        let handoff = IntentServices()
        let parked = Task { try await handoff.current() }
        try await waitUntil { await handoff.waiterCount == 1 }

        await handoff.clear()

        let replacement = try makeStack()
        await handoff.install(replacement, theme: .standard)

        let resolved = try await parked.value
        #expect(resolved.journal === replacement.journal)
    }

    @Test func themeUpdatesAtomicallyWithoutReplacingTheStack() async throws {
        let handoff = IntentServices()
        let stack = try makeStack()
        await handoff.install(stack, theme: .standard)

        await handoff.updateTheme(.alternate)

        let context = try await handoff.currentContext()
        #expect(context.services.journal === stack.journal)
        #expect(context.theme == .alternate)
    }
}

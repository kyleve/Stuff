import Testing
@_spi(Testing) @testable import WhereCore

struct CompatibilityLocationSourceTests {
    @Test func retirementCancelsOneShotAndPermanentlyRejectsRestart() async throws {
        let source = CancellableLocationSource()
        let guarded = try CompatibilityLocationSource(
            base: source,
            store: SwiftDataStore.inMemory(),
        )
        await guarded.start()
        let request = Task { await guarded.requestCurrentLocation() }
        let deadline = ContinuousClock.now.advanced(by: .seconds(5))
        while await !source.requested {
            if ContinuousClock.now >= deadline { throw Timeout() }
            await Task.yield()
        }
        await guarded.retire()
        #expect(await request.value == .unavailable(.cancellation))
        #expect(await source.cancelled)
        await guarded.start()
        #expect(await source.starts == 1)
        await #expect(throws: DataCompatibilityError.accessRevoked) {
            try await guarded.requestPermission()
        }
    }

    private struct Timeout: Error {}
}

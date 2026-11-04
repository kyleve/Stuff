import Testing
@testable import WhereCore

struct DataCompatibilityLocationSourceTests {
    @Test func retirementJoinsDelayedPhysicalStart() async throws {
        let access = try CompatibilityOutputTestSupport.access()
        let base = HeldStartLocationSource()
        let source = DataCompatibilityLocationSource(base: base, access: access)
        let start = Task { await source.start() }
        await base.startGate.waitUntilEntered()
        let retirement = Task { await source.retire() }
        try await DataCompatibilityTestSupport.waitUntil { access.isRevoked }
        await base.startGate.resume()
        await retirement.value
        await start.value
        #expect(await !base.isMonitoring)
        let stops = await base.stops
        await source.start()
        #expect(await base.stops == stops)
        await #expect(throws: DataAccessPermit.AccessError.self) {
            try await source.requestPermission()
        }
    }

    @Test func retirementRejectsLateOneShotAndPreventsNewRequests() async throws {
        let access = try CompatibilityOutputTestSupport.access()
        let base = HeldRequestLocationSource()
        let source = DataCompatibilityLocationSource(base: base, access: access)
        let request = Task { await source.requestCurrentLocation() }
        await base.gate.waitUntilEntered()
        let retirement = Task { await source.retire() }
        try await DataCompatibilityTestSupport.waitUntil { access.isRevoked }
        await base.gate.resume()
        await retirement.value
        #expect(await request.value == .unavailable(.cancellation))
        #expect(await source.requestCurrentLocation() == .unavailable(.cancellation))
        #expect(await base.requests == 1)
    }
}

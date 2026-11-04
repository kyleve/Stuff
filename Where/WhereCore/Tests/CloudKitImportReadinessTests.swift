import Testing
@_spi(Testing) import WhereCore

@MainActor
struct CloudKitImportReadinessTests {
    @Test func completedImportBeforeDiscoveryIsRetained() async {
        let readiness = CloudKitImportReadiness()
        readiness.start()
        readiness.receiveCompletedImport()
        readiness.start()
        #expect(await readiness.waitForImport())
    }

    @Test func timedOutWaitDoesNotDiscardLaterImport() async {
        let readiness = CloudKitImportReadiness(waitTimeout: .zero)
        readiness.start()
        #expect(await !readiness.waitForImport())
        readiness.receiveCompletedImport()
        #expect(await readiness.waitForImport())
    }

    @Test func cancellingOneWaitDoesNotCancelTheOther() async throws {
        let readiness = CloudKitImportReadiness()
        let first = Task { await readiness.waitForImport() }
        let second = Task { await readiness.waitForImport() }
        try await DataCompatibilityTestSupport.waitUntil { readiness.waiterCount == 2 }
        first.cancel()
        #expect(await !first.value)
        #expect(readiness.waiterCount == 1)
        readiness.receiveCompletedImport()
        #expect(await second.value)
    }
}

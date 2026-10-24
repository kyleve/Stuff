@testable import InstallerKitUI
import Testing

@MainActor
struct UpdatePageRefreshTests {
    @Test func cancellationStopsTheRequestAndPreservesTheModel() async throws {
        let fixture = UpdatePageRefreshFixture()
        fixture.client.held = true
        let refresh = UpdatePageRefresh()
        let task = refresh.start(model: fixture.model)
        try await waitForUpdatePage { fixture.client.pending != nil }
        refresh.cancel()
        fixture.client.pending?.resume(returning: fixture.client.catalog)
        fixture.client.pending = nil
        await task.value

        #expect(task.isCancelled)
        #expect(fixture.client.wasCancelled)
        #expect(fixture.model.state.snapshot == nil)
        #expect(!fixture.model.isChecking)
    }
}

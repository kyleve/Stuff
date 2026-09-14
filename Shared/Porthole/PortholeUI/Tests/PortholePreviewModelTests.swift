import Foundation
@testable import PortholeUI
import Testing

@MainActor
struct PortholePreviewModelTests {
    @Test func readinessHooksShareTheLoadedPresentationAcrossRehosting() async throws {
        let model = PortholePreviewModel()
        async let measurement: Void = model.prepare()
        async let capture: Void = model.prepare()
        _ = await (measurement, capture)
        guard case let .ready(controller) = model.state
        else { Issue.record("Fixture preparation failed"); return }
        let session = try #require(controller.sessionID)
        let scope = try #require(controller.origin?.scope)
        guard case let .loaded(snapshot) = controller.loadState
        else { Issue.record("Readiness returned before the actual explorer loaded"); return }
        #expect(snapshot.contexts.count == 1)
        #expect(snapshot.capabilities.count == 1)
        await model.prepare()
        guard case let .ready(rehosted) = model.state
        else { Issue.record("Rehosting lost the fixture"); return }
        #expect(rehosted === controller)
        #expect(rehosted.sessionID == session)
        #expect(rehosted.origin?.scope == scope)
        controller.dismiss()
        await controller.registry.invalidate(scope)
    }

    @Test func cancelledWaiterDoesNotCancelReadinessForTheNextHost() async {
        let model = PortholePreviewModel()
        let cancelledHost = Task { await model.prepare() }
        cancelledHost.cancel()
        await cancelledHost.value
        await model.prepare()
        guard case let .ready(controller) = model.state
        else { Issue.record("Cancelled host prevented fixture readiness"); return }
        guard case .loaded = controller.loadState
        else { Issue.record("Fixture was not loaded"); return }
        if let scope = controller.origin?.scope { await controller.registry.invalidate(scope) }
        controller.dismiss()
    }
}
